# FEATURE MODULE CONTRACT — read this before writing any code

You are adding ONE feature to EasyForge, a Windows no-code game maker. Bricks on a
graph compile to a playable Godot 4 game. Godot 4.7 official builds ONLY — never a
source fork. The compiler is deterministic: bricks are plain JSON Dictionaries that
generate GDScript. The user NEVER writes raw code.

Working directory: `C:/Users/rishi/easyforge`
Godot editor binary: `tools/Godot_v4.7.2-stable_win64_console.exe` (headless)
Smoke test: `tools/Godot_v4.7.2-stable_win64_console.exe --headless res://tests/test_scene.tscn --quit-after 600`
  → the run PASSES only when output contains `=== SMOKE TEST: ALL PASS ===`

---

## THE ONE RULE: you own exactly ONE file

Create **`src/features/<your_slug>.gd`** and nothing else.

You must NOT edit these files — other builders are editing them in parallel and
your changes would collide and corrupt the build:

- `src/compiler/compiler.gd`
- `src/compiler/features.gd`
- `src/compiler/feature_registry.gd`
- `src/compiler/feature_ctx.gd`
- `src/bricks/brick.gd`
- `src/bricks/registry.gd`
- `src/runtime/game_state.gd`
- `src/ui/main.gd`
- `project.godot`
- `tests/**`

The integrator (a separate owner) adds your module path to `features.gd`, adds your
param schema to `brick.gd`, and registers your kind. You just write the module.

---

## How a feature module works

`features.gd` loads your module and calls `register(reg)`. You call `reg.register(...)`
for each brick kind you build.

```gdscript
extends Node
## my_feature — one-line description of what it adds.

func register(reg) -> void:
	reg.register("my_kind", _build)

func _build(b: Dictionary, root: Node, ctx) -> void:
	# read params, create nodes, add them to `root`
	...
```

### The builder signature

```
func _build(b: Dictionary, root: Node, ctx) -> void
```

- `b` — the brick Dictionary. `b["params"]` holds the user's settings.
- `root` — the Node to add your game objects to (already the correct Node2D/Node3D).
- `ctx` — a `FeatureCtx` object (see `src/compiler/feature_ctx.gd`). Read that file
  first; it has every helper you need:

| ctx member | Meaning |
|---|---|
| `ctx.is_3d` | bool — true for a 3D project |
| `ctx.player` | the player Node, or null |
| `ctx.entities` | Dictionary of brick_id -> Node |
| `ctx.controls` | the player's key bindings |
| `ctx.graph` | the BrickGraph, for reading connections |

### FeatureCtx static helpers (call as `FeatureCtx.foo(...)`)

| Helper | Purpose |
|---|---|
| `FeatureCtx.params(b)` | safe params Dictionary (never null) |
| `FeatureCtx.bnum(b, "key", 1.0)` | param as float, with fallback |
| `FeatureCtx.bstr(b, "key", "def")` | param as String, with fallback |
| `FeatureCtx.bbool(b, "key", false)` | param as bool, with fallback |
| `FeatureCtx.bid(b)` | the brick id String |
| `FeatureCtx.solid_texture(w, h, col)` | an in-memory Color texture (NO asset files) |
| `FeatureCtx.keycode("Space")` | key-name → Godot KEY_* int |
| `FeatureCtx.palette_color("gold")` | named color from the shared palette |
| `FeatureCtx.attach_script(node, source)` | compile + attach GDScript; returns Error |

### Optional: seed state before it is reset

If your brick needs a GameState value to exist before the resets wipe it (like the
Variable brick does), ALSO register a seeder:

```gdscript
func register(reg) -> void:
	reg.register("my_kind", _build)
	reg.register_seeder("my_kind", _seed)

func _seed(b: Dictionary, state, ctx) -> void:
	if state != null and state.has_method("set_var"):
		state.set_var("my_key", 0.0)
```

### Optional: build in pass 1 (before entities exist)

Most bricks build in pass 2. If yours must exist before the player does:
`reg.register_pass1("my_kind")`.

---

## Hard rules

1. **No asset files.** All visuals are Godot primitives + procedural color. Use
   `FeatureCtx.solid_texture()`, `BoxMesh`, `SphereMesh`, `CapsuleMesh`, etc.
2. **Never crash the compiler.** Bounds-check every read. A garbage brick must still
   compile to something harmless. Assume `b["params"]` may be missing, null, or
   wrong-typed.
3. **Deterministic output only.** No `randf()` in positions/geometry (fine for
   particles/decoration). No reliance on filesystem, network, or wall-clock.
4. **Generated scripts must compile.** Always check `FeatureCtx.attach_script(...)`
   return value; it pushes an error for you, so a parse failure is visible.
5. **Both 2D and 3D.** Branch on `ctx.is_3d`. 2D uses Node2D/Area2D/CharacterBody2D/
   Camera2D; 3D uses Node3D/Area3D/CharacterBody3D/Camera3D.
6. **GDScript gotchas that have already bitten this codebase:**
   - `for ch in some_string` does NOT iterate characters. Use `while i < s.length(): var ch = s[i]`.
   - Mixed-type ternaries infer Variant: write `var n: Node = A.new() if x else B.new()`.
   - `Camera3D`/`Camera2D` shake uses `h_offset`/`v_offset`, NOT `offset`.
   - Godot auto-renames duplicate-named siblings to `@Class@N`. Don't rely on names
     being unique; count by class when you need to.
   - `Engine.get_singleton("GameState")` may differ from the `GameState` autoload
     identifier. Generated game code must call `GameState.<method>()` by name.
   - `Parallax2D.scroll_scale` is a Vector2, not a float.
   - `Marker3D`/`Marker2D` need `var n: Node = ... if ... else ...`.
7. **Generated game code talks to GameState by name**, e.g. `GameState.add_score(1)`,
   `GameState.set_var("x", 1.0)`, `GameState.get_var("x", 0.0)`, `GameState.play_sound("coin")`,
   `GameState.hit_stop(0.08)`, `GameState.set_time_scale(0.5)`, `GameState.lose()`.

## GameState API available to your generated scripts

`add_score(n)`, `get_var(name, default)`, `set_var(name, v)`, `add_var(name, n)`,
`toggle_var(name)`, `check_win()`, `lose()`, `hit_hazard(body)`, `set_respawn(pos, body)`,
`damage(n)`, `set_max_health(n)`, `play_sound(kind, vol)`, `burst(n, effect, color, at)`,
`set_time_scale(s)`, `hit_stop(seconds)`, plus vars `score`, `lives`, `game_over`, `won`,
`win_target`, `win_condition`, `respawn_position`.

---

## Definition of done

1. `src/features/<slug>.gd` exists, has a `register(reg)` function, and registers at
   least one brick kind.
2. The module parses clean (verify by running the smoke test — a parse error in your
   file shows as `SCRIPT ERROR` / `Parse Error`).
3. The smoke test still prints `=== SMOKE TEST: ALL PASS ===` with **70 or more** checks.
4. You verified your brick actually compiles by adding a temporary probe scene
   `tests/probe_<slug>.tscn` + `tests/probe_<slug>.gd` that builds a graph containing
   your brick, compiles it, and prints the resulting nodes — then **DELETE the probe
   files** before you finish.
5. Report back: the slug, the brick kind names you registered, what nodes each creates
   in 2D and 3D, and any params you expect the integrator to add to `brick.gd`.

Do not report success without actually running the smoke test.
