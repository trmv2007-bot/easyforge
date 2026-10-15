# EasyForge: Core Engine Architecture Gap Analysis
World-class engine architecture (Unity, Unreal, Godot, GameMaker, Construct) mapped onto the EasyForge brick-IR + deterministic Godot 4.7 GDScript compiler.

## 0. Method and baseline

Codebase read directly at `C:\Users\rishi\easyforge` (5,544 lines of GDScript across 15 files). Verified facts about the current architecture:

- `src/bricks/brick.gd` — a Brick is a plain `Dictionary`; the IR is a **flat list** of bricks with `connections` (`{"from_out", "to_brick", "to_in"}`). There is no parent/child field, no nesting, no entity identity.
- `src/compiler/compiler.gd` (2,078 lines) — `compile_graph(graph)` walks the flat list and `add_child()`s every entity to **one** root node, then emits GDScript as string literals. The comment at line 658 is explicit: *"This keeps the deterministic single-scene compiler intact (no change_scene, ...)"*.
- `src/runtime/game_runner.gd` — `play()` calls `_compiler.compile_graph(graph)` from scratch on **every** Play press and mounts the result into a `SubViewport`.
- Undo is one snapshot: `main.gd` keeps a single `_undo_snapshot` Dictionary taken before an AI edit; there is no redo and no history stack.
- `project.godot` sets no `physics/ticks_per_second` override (Godot default 60) and no interpolation toggle.

Where a claim comes from outside the repo it is cited `[n]`; the Sources block at the end is generated mechanically. Claims about EasyForge are repo-verified and uncited.

## 1. Executive summary

EasyForge's IR is a **flat bag of behaviours attached to implicit entities**. Every world-class engine organises the same concepts inside three layers EasyForge currently lacks:

1. **A place structure** (scene tree / node tree) — who contains whom, and therefore what a transform, a lifetime, and a "thing" even mean.
2. **A template layer** (prefab / scene / object) — author once, instantiate many, override per-instance, and fix a bug in one place.
3. **A change layer** (undo/redo, versioning, hot reload, dependency graph) — the machinery that makes a large project *editable* rather than merely *runnable*.

EasyForge has deliberately chosen the honest half: bricks are JSON dicts, so serialization is free and the compiler is deterministic. That is a real advantage over Unity's binary `.uasset` and is worth protecting.

But the flat list does not scale. The `connections` array is the *only* expression of "these things belong together", and because every brick becomes a direct child of one root, a 40-brick graph produces 40 siblings with no grouping. The single largest structural gap is that **a brick set is not a reusable object** — there is no way to define "Slime" once and place twelve of them.

## 2. Feature matrix

Legend: X = ships, ~ = partial, - = absent.

| # | Feature | Unity | Unreal | Godot | GameMaker | Construct | EasyForge |
|---|---|---|---|---|---|---|
| 1 | Scene / node hierarchy | X | X | X | X | X | - |
| 2 | ECS data-oriented storage | ~ | X | - | - | - | - |
| 3 | Prefabs / instancing + variants | X | X | X | X | ~ | - |
| 4 | Composition vs inheritance | X | X | X | X | ~ | ~ |
| 5 | Event bus / signals | X | X | X | X | X | ~ |
| 6 | Serialization / versioning | X | X | X | X | X | ~ |
| 7 | Dependency graph | X | X | X | X | X | - |
| 8 | Undo / redo | X | X | X | X | X | ~ |
| 9 | Hot reload / live edit | X | X | X | - | ~ | - |
| 10 | Project / asset organization | X | X | X | X | X | ~ |
| 11 | Scripting escape hatch | X | X | X | X | X | - |
| 12 | Deterministic fixed timestep | - | - | ~ | ~ | ~ | ~ |
| 13 | Scene streaming / LOD | X | X | X | ~ | ~ | - |

## 3. Feature-by-feature detail

### 3.1 Scene / node hierarchy — Effort **L** · Beginner impact **Critical**
**What it is:** the tree that says what contains what. In Godot a scene is "a collection of nodes organized in a tree structure, with a single node as its root" [2]; in Unreal everything placed in a level is an `AActor` whose behaviour comes from components [9].
**EasyForge today:** the IR is flat. `compile_graph` attaches every entity directly to one root, so there is no notion of a parent, a group, or a transform parent.
**Gap:** you cannot express "the enemy's gun is attached to the enemy", "these six bricks are one vehicle", or "this HUD lives in a UI layer". Grouping is what turns 40 nodes into a level instead of a pile.
**Mapping:** give `Brick` an optional `parent` field (or a `group` field) and have the compiler nest children under their parent's node. Deterministic, JSON-serializable, no code for the user. This is the **prerequisite** for #3, #10, and #13.
**Verdict:** the single most consequential missing primitive. Everything reusable hangs off it.

### 3.2 ECS vs node trees — Effort **L** · Beginner impact **Low** *(deliberately do not build)*
**What it is:** data-oriented storage where entities are ids and behaviour lives in systems iterating packed component arrays. Unity's own framing is that data-oriented design "empowers creativity" by changing how data is laid out rather than by dropping in an API — their DOTS material is explicit that ECS "is not an API that you can incorporate into your project and expect to get great performance" without restructuring data [8][10]. Godot explicitly does not ship ECS; it is an OOP node architecture.
**EasyForge today:** bricks already behave like component *templates*, so EasyForge is conceptually closer to composition-based node trees than to ECS.
**Gap:** none that matters. ECS buys performance at thousands of entities with SIMD-friendly iteration. EasyForge targets beginner 2D/3D games on an RTX 3050, where the scene tree is the right and idiomatic choice — and it is the choice Godot itself makes.
**Verdict:** explicitly out of scope. Build the node tree well (#3.1) instead. Flagged here so the decision is on record rather than an accident.

### 3.3 Prefabs / instancing and variants — Effort **L** · Beginner impact **Critical**
**What it is:** author an object once as a template, place many instances, override individual properties, and edit the template so every instance follows. Unity: "A Prefab Variant inherits the properties of another Prefab, called the base. Overrides made to the Prefab Variant take precedent over the base Prefab's values" [1]. GameMaker states the template/instance split plainly: "the object is the template for the instance, and the instance is what we place in a room" [3]. Godot's equivalent is instancing packed scenes, where "Changing a property on an instance always overrides values from the corresponding packed scene" [2].
**EasyForge today:** absent. Ten coins means ten brick sets, wired ten times. To change coin speed you edit ten bricks.
**Gap:** the brick set is not an addressable, reusable unit. This is the scaling wall — a game with 20 object types and 200 instances is unmaintainable as a flat list.
**Mapping:** promote a selected subgraph to a **Blueprint** brick. The IR gains `blueprints: {id: {graph}}` plus bricks of kind `blueprint` carrying `{blueprint_id, overrides}`. Compiler emits one `.tscn` per blueprint and instances it N times, applying overrides as property assignments. Fully deterministic and JSON-native — this is the highest-value architectural addition in this document.
**Verdict:** #1 or #2 in priority. Without it, project size is capped by manual wiring.

### 3.4 Composition vs inheritance — Effort **M** · Beginner impact **High**
**What it is:** attach reusable behaviour packages to an object rather than deriving subclasses. Unreal's `AActor` is "a container for `UActorComponent` subclasses which define behavior, rendering, and physics" — the documented composition-over-inheritance model [9].
**EasyForge today:** partial. `move`, `collide`, `health`, `animation`, `particles` are already behaviour bricks, and `graph.gd` chains them onto an entity via FLOW connections. The *pattern* is right.
**Gap:** no named behaviour package. A beginner cannot define "Platformer Movement" once and attach it to player, enemy and NPC; they wire the same four bricks three times. There is also no inheritance between brick kinds (an `enemy` cannot be "a coin that also moves").
**Mapping:** a named **Behaviour** = a saved subgraph of behaviour bricks. Attaching it instantiates its bricks under the entity. Cheaper than full blueprints and gets most of the benefit.
**Verdict:** medium-high. Blueprints (#3.3) subsume some of this, so sequence it after.

### 3.5 Event bus / signals — Effort **M** · Beginner impact **High**
**What it is:** decoupled broadcast — a publisher emits, subscribers listen, neither knows the other. Godot's signals implement the observer pattern so nodes "communicate without being tightly coupled"; the standard pattern is "Signal Up, Call Down" via an autoload event bus.
**EasyForge today:** partial. `PortType.EVENT` connections exist and `main.gd` uses real Godot signals for UI (`draft_ready`, `chat_done`). Generated gameplay code, however, reaches into the `GameState` autoload directly.
**Gap:** bricks can only talk to bricks they are **wired** to. "When the player dies, anything that cares should hear about it" is not expressible without drawing a wire to every consumer. Construct's model is the opposite — events filter and pick instances so actions hit every matching instance at once [4].
**Mapping:** a named global event channel. `emit("player_died")` from any brick; a `listen` brick subscribes. Compiler generates a typed signal list on `GameState`. Small change, large expressiveness gain.
**Verdict:** high value for low cost. Best effort-to-impact ratio in this document.

### 3.6 Serialization / versioning — Effort **M** · Beginner impact **Medium** *(high trust impact)*
**What it is:** every save/project file carries a format version written from the very first build, and old data still loads after the schema changes [11][12]. The standard discipline: "Store a version number in every save file, and never assume the shape of the data" [12].
**EasyForge today:** a genuine strength — bricks are plain dictionaries and JSON round-trips exactly, which sidesteps Unity's binary-asset version-control pain entirely [14]. **But there is no version field.** `from_json` parses whatever it is given and has no migration path.
**Gap:** the first brick-rename, param default change, or new required param will silently break existing user projects. This is a *data-loss* bug class, not a missing feature.
**Mapping:** add `schema_version` to the project envelope and a `migrate(dict) -> dict` function keyed by version. Cheap. Should ship before any IR change.
**Verdict:** low effort, and it protects every other change in this document. Do it first.

### 3.7 Dependency graph — Effort **M** · Beginner impact **Medium**
**What it is:** explicit edges between assets so the editor knows what to reimport, what a rename breaks, and in what order to evaluate. Unity tracks assets and their companion `.meta` files so imports are incremental [14].
**EasyForge today:** absent. `connections` is a wiring list, not a dependency DAG, and the compiler walks the flat brick list in array order.
**Gap:** two failure modes. (a) Rebuild order is accidental — a brick reading a variable defined by a later brick depends on list position. (b) Renaming a variable or deleting a brick silently breaks links with no warning.
**Mapping:** derive a DAG from `connections` (it already encodes the edges). Use it to topologically sort compile order, and to detect cycles and dangling references at edit time. Mostly free once the graph is a graph.
**Verdict:** medium. Turns "the compile is wrong and I don't know why" into a specific diagnostic.

### 3.8 Undo / redo — Effort **M** · Beginner impact **Critical**
**What it is:** a command stack where each mutation is a reversible action. Editors implement this with the command pattern so operations are undoable and redoable.
**EasyForge today:** one-shot. `main.gd` holds a single `_undo_snapshot` taken before an **AI** edit; `_on_undo_pressed` restores it and then clears it. There is no redo, no stack, and **manual drags and param edits are not undoable at all**.
**Gap:** a beginner who mis-drags on a 40-brick graph has no recovery. AI edits are the *rarer* case and they are the only ones covered — the coverage is inverted.
**Mapping:** wrap every mutation (add brick, delete, rewire, param change) in a command object pushed to an `UndoRedo` stack. Snapshot diffing is fine at this scale. Both directions, all edit paths.
**Verdict:** top-3. Non-negotiable editor table stakes; its absence makes the tool feel unsafe.

### 3.9 Hot reload / live edit — Effort **M** · Beginner impact **High**
**What it is:** edit while running and see the change apply without restarting. Unity's docs frame it as applying "edited C# to running code without restarting Play Mode or rebuilding the Player" [13].
**EasyForge today:** absent, and structurally far from it. `game_runner.play()` calls `compile_graph()` from scratch on every press, then tears down and rebuilds the entire node tree. Any tweak-while-playing resets all runtime state.
**Gap:** the beginner loop is *tweak → stop → replay from the start → navigate back to the moment you cared about*. For a jump-height feel tweak that loop is measured in tens of seconds and it kills iteration.
**Mapping:** the cheap 80% is parameter hot-patch — on param change during Play, write the new value into the live node instead of recompiling (GameState/`set()` path). Full hot reload means recompiling only the changed brick's script, which is genuinely L.
**Verdict:** high impact, and the cheap version is reachable. Ranked below the three structural items because it improves iteration speed rather than capability.

### 3.10 Project / asset organization — Effort **M** · Beginner impact **Medium**
**What it is:** assets organised by feature/domain rather than by file type, with folders, naming conventions and a project browser. The consensus guidance for large projects is "organize by feature, not by type".
**EasyForge today:** single-graph. One `BrickGraph` autoload; the multi-level work (`_build_extra_levels`, `_compile_level_into`, `_level_manager_source`) exists in the compiler but is bolted onto the single-scene model.
**Gap:** a project is one graph. There is no project tree, no scene list, no place to put "level 3" or "main menu" that is not a hack on the compiler.
**Mapping:** promote the project to a list of graphs (`levels: [...]`) with a project browser. Depends on #3.1 for in-level grouping.
**Verdict:** medium, but it is the unlock for scene streaming (#3.13) and for anything past a one-level demo.

### 3.11 Scripting escape hatch — Effort **M** · Beginner impact **Low** *(high retention impact)*
**What it is:** when the visual system cannot express something, write code. Every competitor ships one: GDevelop has JavaScript Code events, explicitly "only meant to be used by advanced users" [7], plus extensions written in events, JS or both.
**EasyForge today:** none. The user never writes code — that is the core product promise.
**Gap:** the ceiling. Reviews of no-code engines converge on the same complaint — "No-code is great for prototypes and simple mobile games, but it runs into walls fast once a game gets complex", with GDevelop's own reviewers flagging performance ceilings and a maturing 3D toolset [6]. When a user hits the wall they leave the tool entirely rather than graduating.
**Mapping:** an **Advanced** brick that takes a small GDScript body the compiler injects verbatim. Hidden behind a "danger" affordance, never shown in onboarding. The promise "you never *have* to write code" survives intact — it becomes "you never have to, and if you want to, you don't have to leave".
**Verdict:** low beginner impact by design, high retention impact. The graduation ramp.

### 3.12 Deterministic simulation / fixed timestep — Effort **S** · Beginner impact **Medium**
**What it is:** simulation advances in fixed steps from a seeded state so identical inputs produce identical output — the invariant that makes replays and rollback possible: "same inputs + same simulation code = same state".
**EasyForge today:** already substantially there, and better than most. All generated movement runs in `_physics_process` (verified in `compiler.gd`), which Godot drives at a fixed 60 Hz — physics is already decoupled from render framerate. Bricks are static data, `GameState` is a plain store, and procedural sound is generated from a seeded key (`_tone_wav(kind)`). This is a real architectural win.
**Gap:** implicit rather than guaranteed. `project.godot` pins no `physics/ticks_per_second` (inheriting Godot's default 60), interpolation is not configured, and float order of operations is not pinned. Nothing *breaks* it, but nothing *protects* it either — a future brick using `_process`, `randf()`, or unsorted dictionary iteration would silently break determinism.
**Mapping:** S. Pin `physics/ticks_per_second` explicitly in the generated project, enable physics interpolation, ban `randf()` from generated code in favour of a seeded RNG, and add a compiler lint that rejects `_process` for anything gameplay-related.
**Verdict:** cheap insurance on an existing advantage. Worth doing early precisely because it is nearly free.

### 3.13 Scene streaming / LOD — Effort **L** · Beginner impact **Low** *(today)*
**What it is:** load and unload world chunks by proximity so large worlds stay in budget — Unity's additive async loading "does not destroy objects in the current level" [15] — plus mesh LOD and visibility ranges, which Godot documents as usable with "any node that inherits from `GeometryInstance3D`" and combinable with automatic mesh LOD on the same mesh [5].
**EasyForge today:** absent, and by design the compiler avoids `change_scene` in favour of one built scene (explicit comment at `compiler.gd:658`).
**Gap:** no. This is the one gap that is *correct to have*. Streaming exists for large worlds; EasyForge builds small ones. Adopting it now would add chunk management, load/unload lifecycle and a proximity system to solve a problem beginners do not have — and it would fight the deterministic single-scene compiler that is currently the project's biggest strength.
**Mapping:** none now. When (and only when) projects get big enough that the single scene loads slowly, the first step is not streaming — it is `load()`ing level scenes lazily on door entry. Full streaming stays out of scope.
**Verdict:** explicitly deferred. Recorded so it is a decision, not an oversight.

## 4. Top 5, ranked

Ranked by (beginner impact x unblocking power) / effort. "Unblocking" means how much else becomes possible once it ships.

**1. Blueprints (prefab / instancing + variants) — §3.3 · Effort L · Impact Critical**
The scaling wall. Ten coins = ten brick sets today; after this, one blueprint instanced ten times with per-instance overrides. Unblocks multi-level projects (#3.10), streaming (#3.13), and the genre packs. Fix a bug once, not forty times. Highest unblocking power of anything here.

**2. Scene / node hierarchy — §3.1 · Effort L · Impact Critical**
The prerequisite. The IR is a flat bag, so "these bricks are one thing" is inexpressible. Every other structural item — blueprints, project organization, behaviours — needs a parent/child field to hang from. Cheapest per unit of structural leverage if scoped to an optional `parent` field plus compiler nesting.

**3. Real undo/redo — §3.8 · Effort M · Impact Critical**
Currently inverted: the *only* undoable action is the rare AI edit, while every manual drag and param tweak is unrecoverable. A command stack across all edit paths is what makes a 40-brick graph feel safe to touch. Medium effort, no architectural risk, and it is table stakes for any editor.

**4. Schema versioning + migration — §3.6 · Effort M · Impact Low/Medium beginner, High trust**
Effort is low, but the failure mode is data loss: the first IR change silently orphans every existing user project. EasyForge's JSON-dict IR is a genuine advantage over Unity's binary assets — this is what keeps it one. Must ship *before* items 1 and 2, because those two change the IR.

**5. Event bus / named global signals — §3.5 · Effort M · Impact High**
Best effort-to-impact ratio in the document. Bricks can currently only talk to bricks they are wired to, so "when the player dies, everything that cares should know" costs a wire per consumer. A named event channel plus a `listen` brick is a small compiler change with a large expressiveness gain.

**Recommended sequence:** #4 first (it is the safety net for the IR changes), then #2 (the primitive), then #1 (the payoff), then #3 and #5 (independent, either order). §3.2 (ECS) and §3.13 (streaming) are deliberately deferred, and §3.12 is a cheap same-week win.

## Sources

[1] Unity — Prefab Variants: https://docs.unity3d.com/2021.3/Documentation/Manual/PrefabVariants.html
[2] Godot Docs — Creating instances: https://docs.godotengine.org/en/4.7/getting_started/step_by_step/instancing.html
[3] GameMaker Manual — Objects And Instances: https://manual.gamemaker.io/lts/en/Quick_Start_Guide/Objects_And_Instances.htm
[4] Construct 3 Manual — How events work: https://www.construct.net/en/make-games/manuals/construct-3/project-primitives/events/how-events-work
[5] Godot Docs — Visibility ranges (HLOD): https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html
[6] Egmatic — GDevelop Review 2026: Free No-Code Engine, Real Limits: https://egmatic.com/blog/gdevelop-review-is-this-no-code-engine-worth-it
[7] GDevelop Wiki — JavaScript Code events: https://wiki.gdevelop.io/gdevelop5/events/js-code/
[8] Unity — On DOTS: Entity Component System: https://unity.com/blog/engine-platform/on-dots-entity-component-system
[9] Epic Games — Introduction to C++ Programming in UE4 (Actors and Components): https://dev.epicgames.com/documentation/en-us/unreal-engine/introduction-to-cplusplus-programming-in-ue4
[10] Unity Learn — Understand data-oriented design (DOTS best practices): https://learn.unity.com/course/dots-best-practices/tutorial/part-1-understand-data-oriented-design
[11] Crown Ashes — Save Systems and Serialization: https://crownashes.com/articles/save-systems-serialization/
[12] Egmatic — Save Systems Explained: https://egmatic.com/blog/save-game-progress-save-system-guide
[13] Unity Pipeline Docs — Hot reload: https://docs.unity3d.com/Packages/com.unity.pipeline@0.6/manual/hot-reload.html
[14] Game Developer — The complete guide to Unity & Git: https://www.gamedeveloper.com/programming/the-complete-guide-to-unity-git
[15] Unity ScriptReference — LoadLevelAdditiveAsync: https://docs.unity.com/en-us/engine/6000.3/script-reference/unityengine/application/loadleveladditiveasync
