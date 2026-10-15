# AUTONOMOUS BUILD PLAN — read this first, every run

You are continuing an overnight autonomous build of **EasyForge**, a Windows no-code
game maker in `C:/Users/rishi/easyforge`. Bricks on a graph compile to playable Godot 4
games. Godot 4.7 official builds ONLY (no source fork), deterministic bricks(JSON)-to-
GDScript compiler, user never writes raw code, local standalone games, assets are Godot
primitives plus procedural color only.

Rishi is ASLEEP. Do not wait for input. Do not ask questions. Make the call yourself and
document it. When one wave lands: integrate it, verify it, rebuild, then dispatch the
next. Keep going until every wave in the plan is done, then run the final audit.

---

## HARD RULES (never break these)

1. **Godot 4.7 official only.** No source fork. If a feature needs an engine change,
   reject it and pick another.
2. **Never edit these files directly from an agent.** You (the integrator) own them:
   `src/compiler/compiler.gd`, `src/compiler/features.gd`,
   `src/compiler/feature_registry.gd`, `src/compiler/feature_ctx.gd`,
   `src/bricks/brick.gd`, `src/runtime/game_state.gd`, `project.godot`.
   Parallel builders must not touch them — that is what corrupts the build.
3. **One file per builder.** Each subagent writes exactly one new file under
   `src/features/<slug>.gd`. Read `FEATURE-CONTRACT.md` and paste it into every task's
   context verbatim.
4. **VERIFY, do not trust.** A builder's self-report is not evidence. After integrating,
   ALWAYS run the two checks below. Both must be clean before you call a wave done.
5. **The placeholder check is mandatory.** Compile a graph containing every new brick and
   assert NO node is a `Label3D`/`Label` placeholder. A placeholder means the module
   silently failed to load and the brick does nothing. Checking only "scripts parse" is
   how bugs shipped twice already.
6. **If the build breaks, fix it before moving on.** Never dispatch the next wave on a red
   build. Revert the offending module file if needed (delete it and drop its line from
   `features.gd`), get back to green, then re-dispatch that single task.
7. **Delete every probe file** a builder leaves in `tests/` before finishing.
8. **Never claim a feature works because the smoke test passes.** The smoke test does not
   cover feature bricks. The placeholder check + a targeted probe is the real proof.
9. **Honesty over claims.** If something cannot be done within the constraints, say so
   plainly and pick a different item. Do not fake output or invent results.

---

## THE LOOP (repeat per wave)

For each wave:
1. `delegate_task` with the wave's tasks. Paste FEATURE-CONTRACT.md content into every
   task's `context`. Give each builder a unique slug and say "YOUR FILE ONLY:
   src/features/<slug>.gd".
2. **END YOUR TURN.** Results arrive as a new message. Do not poll.
3. On arrival: read each module. Fix parse errors yourself (do not re-dispatch for a
   one-line syntax fix).
4. Register: add the module path to `_MODULES` in `src/compiler/features.gd` (alphabetical).
5. Add the brick kind to `BrickRef.KIND`, its params to `PARAM_SCHEMA`, and its defaults
   to `create()` in `src/bricks/brick.gd`.
6. Add its inspector sections in `src/ui/main.gd` `_sections_for`, and escape-hatch lines
   in `compiler.gd` `generated_script`.
7. Extend the `feat_kinds` array in `tests/smoke_test.gd` with the new kinds.
8. Verify: smoke test must be ALL PASS, and a probe must show 0 placeholders / 0 parse
   failures for the new bricks in BOTH 3d and 2d.
9. Rebuild: `tools/Godot_v4.7.2-stable_win64.exe --headless --export-release "Windows Desktop" build/EasyForge.exe`
10. Append a short wave summary to `BUILD-LOG.md`.
11. Dispatch the next wave.

---

## VERIFY COMMANDS

Smoke:
```
cd /c/Users/rishi/easyforge && tools/Godot_v4.7.2-stable_win64_console.exe --headless res://tests/test_scene.tscn --quit-after 600 2>&1 | grep -E "\[FAIL\]|SMOKE TEST|checks run|Parse Error|SCRIPT ERROR"
```
UI:
```
cd /c/Users/rishi/easyforge && tools/Godot_v4.7.2-stable_win64_console.exe --headless res://tests/ui_test_scene.tscn --quit-after 600 2>&1 | grep -E "UI TEST|\[FAIL\]|palette has"
```
Build:
```
cd /c/Users/rishi/easyforge && tools/Godot_v4.7.2-stable_win64.exe --headless --export-release "Windows Desktop" build/EasyForge.exe
```

---

## CURRENT STATE (update this as you go)

- Palette: **50 bricks**. 21 feature modules, 24+ registry kinds. Smoke **94/94**
  ALL PASS, UI **31/31** ALL PASS. `build/EasyForge.exe` rebuilt 11:51, launches
  clean. `tests/` and `tools/` contain no probe leftovers.
- Waves 5-12 landed, plus WAVE 15 (usability + silent-brick fixes) — see the end
  of `BUILD-LOG.md` for exactly what was verified by execution and what was not.
- WAVE 8 items are DONE (schema version 2 in `graph.gd`, named input actions via
  `inputmap.gd`, event bus, real undo/redo). WAVE 9-12 items are DONE (light,
  errors, watch, widgets, blueprint, hierarchy, rigid, perceive, theme, bind/hud).
- **New tool**: `python tools/gen_locales.py` regenerates `src/i18n/locales.gd`
  from the tab-separated `i18n/locale_*.csv` AND lints for missing/untranslated
  keys. Run it after any CSV edit; its warnings are the bug list.
- **New lock**: the smoke "footprint sweep" fails any palette kind that compiles
  to a tree identical to baseline. When you add a brick, it must pass this or be
  explicitly whitelisted with a stated reason (state/config-only).
- **NEXT, in order** (all measured, all still open):
  1. **2D pathfinding has no navmesh at all** — probed: in a 2D graph the pathfind
     brick ships no `NavigationAgent2D` and no `NavigationRegion2D`
     (`agent=false, nav_region=false`), so the mover runs `_move_plain` and walks
     straight into geometry (measured: pinned 180/300 frames at a wall edge). The
     brick promises "a smart enemy that walks around walls" and most beginner
     games are 2D. Biggest remaining honesty gap. `src/features/pathfind.gd:33-40`,
     `:142-145`.
  2. Arabic is translated but not RTL (nothing sets `layout_direction` /
     `text_direction`).
  3. `rigid` `start_asleep` is still a no-op (measured: the body fell anyway).
  4. `menu.gd._screens` persists between compiles — confirmed by a signature-diff
     test that tripped on it; check whether Play-after-edit is affected.
  5. Providers still never exercised live: **Gemini and Ollama**, plus Phase B
     (`finalize`) and a chat-edit round-trip on any provider.
- **AI latency is now measured, not assumed**: Groq `openai/gpt-oss-120b` drafts a
  valid 10-brick graph in **~6s** through the app's own HTTP client (zero
  validation problems, 29ms compile). NVIDIA `z-ai/glm-5.3-flash` gives a richer
  18-brick graph but takes **~170s**. Default provider is now `groq`.
- **Live AI draft PROVEN (wave 17)**: real key, real network — 19 bricks, zero
  `validate()`/`validate_ir()` problems, compiled to a real 3D scene. Default
  model is `z-ai/glm-5.3-flash` (~170s). Budgets are 12288 tokens for a reason.
- **Proven this wave — do not redo**: 3D `pathfind` really does route around a
  solid wall and reach the player (19.10 -> 1.39, waypoint index advances to 7,
  defaults pass too, and forcing the threshold back to 0.5 reproduces the original
  pin, so the cause is confirmed). Also fixed and verified: the 2D arrive radius
  was unreachable (enemy pressed into the player forever), `_find_player()` could
  chase a hidden sibling level's player, all 17 AI error strings moved off the
  dead `tr()` path onto `I18n.t()` in 10 languages, and Settings now accepts a
  typed model id so a retired hosted name can't brick the AI.
- **Known gotcha added this wave**: `res://` inside an exported .exe is the PCK,
  not the exe's folder. Files that ship beside the binary must be resolved via
  `OS.get_executable_path().get_base_dir()`. This broke the game exporter's first
  version and was only caught by actually launching the exported exe.
- `NavigationMesh.GEOMETRY_STATIC_COLLIDERS` is NOT reachable from GDScript —
  do not try to set it again; it breaks parsing.
- This project is **not a git working tree**. Snapshot before big changes:
  `cp -r src tests i18n *.md <dir>` (this run: `~/easyforge-snapshot-2026-10-13/`).

## KNOWN GOTCHAS (already bitten this codebase — do not repeat)

- `Engine.has_singleton("X")` returns FALSE for our autoloads. Resolve via
  `get_node_or_null("/root/X")`. This silently disabled the whole feature registry once.
- Bare `_ = value` is NOT valid GDScript. It broke `look.gd` and cascaded to kill two
  other modules (features.gd loads alphabetically, so one parse error kills the rest).
- Generated code containing `%` inside a `%`-formatted string needs `%%`, or better, use
  string concatenation. This corrupted the save path.
- Godot auto-renames duplicate-named siblings to `@Class@N`. Never rely on node names
  being unique; count by class.
- `Camera3D`/`Camera2D` shake uses `h_offset`/`v_offset`, not `offset`.
- `Parallax2D.scroll_scale` is a Vector2. `Vector2.clampf()` does not exist (use
  `limit_length`). `for ch in some_string` does not iterate characters — index it.
- Mixed-type ternaries infer Variant and fail: write `var n: Node = A.new() if x else B.new()`.
- A signal connected at COMPILE time to the module node dangles in the exported game
  (that node does not exist there). Wire signals inside generated `_ready()`.
- A Label placed as a ROOT child will trip the placeholder check. Feature labels must be
  children of their entity.
- A brick that adds ZERO nodes is invisible to the placeholder sweep — it looks like
  success. The smoke "footprint sweep" (per-kind tree signature) is the only lock that
  catches it. Five bricks shipped inert this way.
- `PhysicsDirectSpaceState3D.intersect_ray` is unusable in this headless build
  (`Required object "rp_ray_query" is null`). Prove solidity with a StaticBody + shape
  and the observed trajectory instead.
- `get_first_node_in_group("player")` is tree-global: mount two scenes in one process and
  the second silently hijacks the chase. Run ONE mounted case per probe process.
- Godot's `tr()` does NOT translate this project's strings: it needs a CSV whose first
  column is the English text, and ours uses identifier keys. Use `I18n.t()`. Locked by a
  smoke check.
- **Every free NVIDIA model that answers is a REASONING model.** Measured: the thinking
  tokens consume the whole completion budget, so a small `max_tokens` yields HTTP 200 with
  **empty** content. Draft/finalize/edit need **12288**; `test_key` needs ~512. Never
  treat an empty answer as a bad key.
- NVIDIA's `GET /v1/models` is NOT a list of what works: ~80 ids are returned and most
  404 on `chat/completions` for a free key (qwen, minimax, kimi, mistral-large,
  codestral, gemma, granite all 404'd). Only `z-ai/glm-5.3-flash` and `openai/gpt-oss-20b`
  drafted valid graphs; `nemotron-3.5-lightning` never answered. Don't populate a picker
  from that endpoint.
- `str(null)` in GDScript is the literal string `"<null>"`, which passes an
  `is_empty()` check. Read nullable JSON fields as a Variant and test for `null` first —
  this made a null AI answer look like a 6-character reply.
- A truncated (partial) JSON reply is a different failure from a garbled one; check
  `finish_reason == "length"` and tell the user to shorten the idea.
- **Neither provider's model list is trustworthy.** NVIDIA `/v1/models` returns ~80
  ids and most 404 on chat; the Groq key lists 11 and only 2 are usable (qwen3.8-27b
  is org-blocked; llama-3.3-70b / llama-3.1-8b / llama-4-scout / kimi all 404).
  Measure before adding a name, and keep the free-text model box.
- **HTTP 403 `error code: 1010` from Groq = Cloudflare client ban, not a bad key.**
  Python's default urllib signature gets blocked; `User-Agent: GodotEngine` does not.
  The app itself is fine — don't "fix" it by adding headers without testing.

---

## REMAINING WAVES

### WAVE 8 — Tier 0 IR foundations (HIGHEST PRIORITY, do these yourself, not via agents)
These change the IR, so the integrator must do them directly.
1. **Schema versioning + migration.** `graph.gd`'s `from_dict()` accepts any shape with no
   version field, so the first brick rename silently orphans every existing user project.
   Add `schema_version` to `to_dict()`/`from_dict()` and a `migrate(dict)` that upgrades
   older dicts. Ship BEFORE blueprints/hierarchy change the IR further.
2. **Named input actions.** The movement script bakes raw KEY_* ints. Compile brick inputs
   to named Godot InputMap actions so gamepad/touch/rebinding become cheap. Users still
   pick keys from dropdowns. This is the keystone for later input work.
3. **Event bus / named global signals.** Bricks can only talk to bricks they are wired to.
   Add a named event channel on GameState plus a "listen" brick so "when the player dies,
   everything that cares should hear" costs one call instead of one wire per consumer.

### WAVE 9 — visible quality, low risk (agents)
- `light`: 2D lights + shadows (Light2D + LightOccluder2D; Godot's SDF occluders make
  sprite shadows free). Highest visual impact per effort in 2D.
- `errors`: friendly error reporting UI — link each IR issue to its brick, plain language,
  suggested fixes. Most machinery exists in `validate_ir()`.
- `watch`: live value inspection — watch/edit any Variable live while the game runs.
- `widgets`: a UI widget library (button/slider/toggle/dropdown) + responsive layout.

### WAVE 10 — major M/L unlocks (agents, but integrate carefully)
- `blueprint`: prefab/instancing with overrides. The biggest unlock in the survey: today
  ten coins = ten hand-wired brick sets. Requires `blueprints` in the IR + a `blueprint`
  kind that instances N times. **Depends on WAVE 8 schema versioning.**
- `hierarchy`: optional parent field so "the gun is attached to the enemy" is expressible.
  **Depends on schema versioning.**
- `rigid`: rigidbody dynamics as a body mode (mass/force/damping) — falling crates, dice,
  stacking. Native RigidBody2D/3D, deterministic at fixed 60Hz.

### WAVE 11 — depth (agents)
- `audio_bus`: audio buses + mixing (Music/SFX/UI routing, volume sliders).
- `hotreload`: hot-reload/live-edit — value changes apply while the game runs.
- `perceive`: perception brick (sight cone, hearing, line-of-sight, memory).
- `btree`: behavior tree brick (nested selector/sequence + decorators).

### WAVE 12 — polish (agents)
- `touch`: touch/mobile controls (Godot 4.7 VirtualJoystick + touch buttons + gestures).
- `theme`: UI style/theme presets + screen transitions (fade/slide tweens).
- `bind`: data-binding via GameState signals + a HUD kit (health bar, inventory, minimap).
- `particles2`: particle upgrades (gradients over lifetime, emission shapes).

### WAVE 13 — engine breadth (agents)
- `camstack`: camera composition (SubViewport stack + visibility layers) — minimaps,
  split-screen, portals.
- `joint`: joints (hinge, spring, slider, pin).
- `quality`: one Graphics Quality preset (renderer + FXAA->MSAA->TAA + scaling + vsync).
- `trace`: event tracing / visual logging — brick-named execution log answering
  "why didn't X happen".

### WAVE 14 — finish (agents + integrator)
- `screen_proc`: procedural Screen brick — one brick compiles to a fully styled,
  navigable, data-bound screen. Our structural advantage over Unity/Godot/RPG Maker.
- `split2p`: local same-machine split-screen / hotseat multiplayer (zero networking).
- `replay`: replay via determinism (input recording + deterministic resimulation).
- `telemetry`: local-first on-disk telemetry, opt-in, GDPR-clean.

### FINAL — audit (integrator, with a review team)
When every wave above is done:
1. Full verification: smoke, UI, clean release-exe launch, 0 errors.
2. Confirm every registered kind appears in the palette and in the inspector with working
   controls.
3. Confirm no probe leftovers in `tests/`, no dead modules in `features.gd`.
4. Dispatch a 4-agent audit team in parallel, each read-only, covering:
   (a) correctness — does every brick actually build a real node and behave;
   (b) robustness — garbage/partial/null params never crash the compiler;
   (c) constraint compliance — no engine fork, no raw code exposure, deterministic;
   (d) gaps — what from GAP-ROADMAP.md is still missing, ranked.
5. Fix everything the audit finds that is real. Re-verify. Rebuild.
6. Write the final report into `BUILD-LOG.md` and tell Rishi plainly what shipped, what
   was verified by execution, and what was consciously deferred or rejected.

---

## REPORTING

Rishi reads these when he wakes. Be plain and honest. State what actually shipped, what
you verified by RUNNING it, what you fixed, and what you could not do and why. Never
inflate. If a feature is partial, say it is partial.
