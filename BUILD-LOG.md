# EasyForge — Build Log (overnight autonomous build)

**Started:** 2026-10-09 ~22:19 IST · **Finished:** 2026-10-10 (early)
**Builder:** Hermes Agent, full autonomy — Rishi away, every unknown decided
and documented here. No stops for input.

## Outcome

**v1 vertical slice — working, tested, 31 automated checks passing, 0 failures,
0 script errors.** The full pipeline runs: bricks -> compile -> playable game ->
export.

## Autonomous decisions (made without Rishi)

| # | Decision | Reason |
|---|---|---|
| 1 | Godot 4.7.2-stable, portable in `tools/` | Latest stable; portable = zero admin, uninstall = delete folder. Verified `--version`. |
| 2 | Compiler + UI in GDScript, not Python | One codebase = the app itself; runnable headless for tests. |
| 3 | Built the engine custom, NOT forked Assistant Pro | Fork = untested external code mid-night; custom = full control, testable tonight. Same pipeline architecture either way. |
| 4 | Hardcoded platformer demo proves the full pipeline with zero API key | All API keys ABSENT on the box; AI layer is wired + ready, activates when Rishi adds a key. App is genuinely playable with no key. |
| 5 | In-app Play = mount the compiled scene into a SubViewport | "Hit Play inside the app, no separate window" (user's words). |
| 6 | Bricks reference models by name; v1 uses Godot primitives | No Kenney download tonight (external dep); primitives are the documented v1 fallback in SPEC. |
| 7 | LLM client = one OpenAI-compatible HTTP path for NVIDIA + Gemini + Ollama | All three speak it; one code path, three providers. |
| 8 | 10 languages via CSV + autoload translator | en, hi, es, zh, ar, pt, fr, de, ja, ru — user's "top 7-10 widely known"; text-only = tiny storage. |
| 9 | Errors never crash — caught, shown in status bar | Friend will hit AI bugs; the app must survive them. |
| 10 | Tests run as scenes, not `--script` | `--script` runs BEFORE autoloads register, so autoload identifiers don't resolve. Scene-based tests run under the real app conditions. |

## Timeline

- 22:19 Godot downloaded + unzipped + `--version` verified (4.7.2.stable.official)
- ~22:25 Brick IR (`brick.gd`), `graph.gd`, `registry.gd` written
- ~22:40 Compiler (`compiler.gd`) — the deep module — written
- ~22:55 AI layer (`llm_client.gd`, `brick_generator.gd`), runtime, i18n, settings
- ~23:10 All 10 locale CSVs written
- ~23:20 UI (`main.gd`, `main.tscn`) built
- **First import:** 6 parse-error classes. Fixed in order:
  1. autoload name collides with `class_name` (Brick/BrickGraph/BrickRegistry/Compiler)
  2. `connect()` overrides `Object.connect()` -> renamed to `wire()`
  3. autoloads must `extend Node` (RefCounted rejected)
  4. `GameState` had no autoload entry (generated code called `GameState.*` -> runtime fail)
  5. `:=` type inference on Variant/conditional-type values (warnings-as-errors)
  6. `.tscn` was accidentally a GDScript file (structural mistake, rebuilt)
- **Smoke test v1:** ALL PASS but 2 hidden bugs surfaced:
  - generated coin-collector script had a tab-indent mismatch -> parse error, script silently not attached
  - `Camera3D.look_at()` called outside the tree
- Fixed both; added checks that every generated script `reload()`s clean.
- **Smoke test v2:** 22 checks, ALL PASS, 0 errors.
- **First app launch:** 8 more errors in `main.gd` (type inference, wrong `set_slot` signature, SubViewport size_flags on a non-Control). All fixed.
- **App launches clean: 0 errors.**
- **UI test built** (drives the real UI like a user). Found + fixed:
  - collector script attached to wrong node (`get_parent()` indirection bug)
  - export dir didn't exist -> export silently failed
- **UI test: 12 checks, ALL PASS.**
- Final: **31 checks pass, 0 fail, 0 script errors.**

## Bugs found and fixed (the honest list)

1. **Autoload/class_name collision** — a `class_name` matching an autoload is a parse error in Godot 4.7. Renamed to `BrickRef`; removed `class_name` from autoload scripts entirely.
2. **`connect()` override** — GDScript rejects overriding `Object.connect()`. Renamed to `wire()`.
3. **Autoloads must extend Node** — `RefCounted` autoloads fail to instantiate.
4. **GameState not registered** — generated game scripts reference the `GameState` singleton; it wasn't in `project.godot`'s autoload list. Runtime crash waiting to happen.
5. **Generated-code indent bug** — `GameState.add_score(1)` emitted at 1 tab inside a 2-tab `if` block -> parse error -> script silently unattached. The smoke test now *reloads every generated script* to catch this class of bug.
6. **Camera outside tree** — `look_at()` before `add_child()`. Switched to `look_at_from_position()`.
7. **`set_slot()` signature** — Godot 4 takes 7 positional args (+2 optional textures), not the 11 I wrote.
8. **SubViewport is a Node, not a Control** — wrapped in `SubViewportContainer` to render in the UI.
9. **Export dir missing** — `user://exports/` wasn't created before writing; export silently failed.
10. **Collector attached to wrong node** — used `get_parent()` assuming the Area was the parent; it *is* the node the script is on. Now connects by signal name on `self`.
11. **`--script` vs autoloads** — headless `--script` mode runs before autoloads register. Tests rebuilt as scenes (also more faithful to real app conditions).

## What's shipped (verified working)

- Brick IR (5 universal kinds + platformer pack = 9 palette bricks)
- Compiler: bricks -> playable Godot 4 GDScript + scene (3D **and** 2D)
- Graph editor: render, add from palette, typed-port connect/disconnect, per-brick comments
- In-app Play: mounts/unmounts the compiled game in a SubViewport
- Code view (the Visual/Code escape hatch)
- Export to a local `.efg` file
- BYOK settings: NVIDIA / Gemini / Ollama, paste key, **Test key** before use
- 10-language UI
- Guided first-run tutorial (never an empty canvas — demo auto-loads)
- Zero-key playable demo (Coin Dash platformer)

## What's deliberately NOT in v1

- 3D Model Maker (v2, fully designed in SPEC.md §10)
- User-own asset import, AI image-gen
- Genre packs beyond the platformer demo
- Full Kenney asset packs (primitives are the documented v1 fallback)
- Live/stream integration, marketplace, hosting (all cut by the user)

## Notes for Rishi

- To ship the friend a **true single .exe**: Godot needs export templates once
  (`Editor -> Manage Export Templates -> Download`), then
  `Project -> Export -> Windows Desktop`. Until then `RUN.bat` is the one-click
  path and deleting `tools/` is a clean uninstall.
- The AI path is wired and code-reviewed but **untested against a live API**
  (no key on the box). First real test: paste an `nvapi-` key, describe a game,
  watch the draft come back. See README "Get a free AI key".

---

## Completion pass (2026-10-10, after the overnight build)

Rishi asked: "is it a fully releasable product with good looks?" Honest answer
was no — it was a working vertical slice with leaked i18n keys and a raw theme.
This pass finished it.

**Dispatched 2 parallel subagents:**
- Task 0 (UI): fixed the i18n leak (all `tr()` -> `I18n.t()`), added keys.
- Task 1 (compiler): hardened `compile_graph()` so it never throws on garbage
  / AI-generated graphs; implemented enemy_patrol, hazard, checkpoint, and
  moving_platform as real bricks; added lighting + multiple coins so the
  compiled game looks alive.

**I built by hand (subagents + me):**
- Full dark design system in code (`_build_theme()`): panels, buttons with
  hover/pressed states, inputs with focus rings, styled GraphNode/GraphEdit,
  dialogs. Purple accent primary action. Design tokens as constants.
- Replaced raw-JSON params in graph nodes with readable bullet summaries.
- Primary "Build with AI" button styled as the accent CTA.

**Critical i18n bug found via the release build (the big one):**
- The editor showed correct text, but the EXPORTED .exe leaked raw keys
  (`app_title`, `tagline`, ...). Root cause: raw `FileAccess` on `res://` CSVs
  fails inside a PCK — only the imported Translation resource is packed, and
  `load()` on the `.csv` path also returned null in export.
- Fix: embed ALL translations as a GDScript constant dictionary
  (`src/i18n/locales.gd`, auto-generated from the CSVs by `tools/gen_locales.py`).
  `i18n.gd` now reads that dict. Verified working in BOTH editor and release
  (English/Hindi/Japanese all resolve; unknown keys pass through safely).
- Also fixed: `I18n.LANGUAGES` -> `available_languages()`/`language_label()`,
  and a `var x :=` inference error at main.gd:602 the probe caught.

**Real .exe shipped:**
- Downloaded Godot 4.7.2 export templates (1.28GB .tpz = a zip), extracted the
  two Windows templates into `%APPDATA%/Godot/export_templates/4.7.2.stable/`,
  ran `--export-release "Windows Desktop"` -> `build/EasyForge.exe` (109MB).
- No editor, no console wrapper, clean "EasyForge" window title.

**The "debug overlay" was a false alarm:** the FPS/GPU/CPU telemetry in
screenshots is `NVIDIA Overlay.exe` + RivaTuner `DesktopOverlayHost` running
system-wide on this machine — it draws over EVERY app. It is not part of
EasyForge. Verified: no Performance-monitor methods are even called.

**Final verification (all real, all passing):**
- App launch: 0 script/parse errors.
- Smoke test: ALL PASS. UI test: ALL PASS.
- Release exe: i18n resolves correctly (English/Hindi/Japanese), zero keys leak.

---

## Polish pass 2 (2026-10-10, after first-user testing feedback)

Three real bugs Rishi hit, all fixed + locked with tests:

1. **Bricks were too tall.** Each GraphNode stacked a 64px TextEdit comment
   box + one-bullet-per-line params, making nodes ~70-80% comment box.
   Fix: comment is now a compact single-line `LineEdit` (`expand_to_text_length`),
   params render inline (`• Speed 12.0   • Jump 12.0`) at font 10, row spacing
   tightened 240->200. Nodes are now short and scannable.

2. **Stop didn't stop after starting.** Root cause: `GameRunner.play()` called
   `stop()` internally, and `stop()` emitted `game_stopped`, whose handler set
   `play_btn.button_pressed = false` DURING the pressed=true toggle — so the
   button got force-unpressed right after the game started, leaving stale state.
   Fix: split into `_teardown()` (internal cleanup, no signal) used by `play()`,
   and `stop()` (teardown + emit) used only for the user-facing stop. Stop now
   unmounts AND resets the button; Play works again after Stop. Locked by a
   strengthened UI test (button_pressed check + restart-after-stop check).

3. **No brick context menu.** Right-click a brick now opens Copy / Paste /
   Duplicate / Delete. Copy/Paste use an in-app `_clipboard` (deep-duplicated
   brick, fresh id, connections cleared). New i18n keys (brick_copy/paste/
   duplicate/delete/copied/pasted) added to all 10 languages + regenerated
   locales.gd (now 49 keys).

Also added: **WASD + arrow-key graph panning** (`_unhandled_key_input` pans
`graph_edit.scroll_offset`; Shift = faster; ignored while a text field has
focus so typing still works).

Final: app launch 0 errors, smoke ALL PASS, UI 14 checks ALL PASS, release
exe rebuilt (build/EasyForge.exe, 23:41).

---

## Polish pass 3 (2026-10-10): full-window Play mode

Rishi's ask: "after I click play it should make the game full windowed and WASD
should bind to the game not the brick graph; after stop, keep the brick editor."

Restructured the layout into two views that swap:
- **Editor view** (`editor_root`): the existing left/center/right split with the
  brick graph, palette, prompt, code panel, and a small preview viewport.
- **Game view** (`game_view`): a full-window overlay — dark backdrop, a red
  "■ Stop (Esc)" bar at top, and the game in a stretched SubViewport below it.

Flow:
- **Play** (`_start_game`): validate -> save -> compile+mount into the GAME
  viewport -> hide `editor_root`, show `game_view`. Game is now full-window.
- **Stop** (`_stop_game`): unmount -> hide `game_view`, show `editor_root`,
  reset the Play button. Also bound to the red Stop button AND the Esc key.
- **WASD/arrows**: `_unhandled_key_input` now only pans the graph when
  `editor_root.visible` is true. During play the editor is hidden, so WASD/arrow
  keys pass through to the game instead of scrolling the node canvas.

Verified by new UI test assertions: "Play switched to full-window game view
(editor hidden)", "Stop returned to the brick editor", plus the existing
stop/restart checks. Final: launch 0 errors, smoke ALL PASS, UI 16 checks ALL
PASS, release exe rebuilt (build/EasyForge.exe, 23:50).

---

## Polish pass 4 (2026-10-10): drag-to-place, camera brick, editable settings

Three asks from Rishi + one bug he hit:

1. **BUG: adding a brick disconnected everything / wiring broke.**
   Root cause: (a) `_add_brick` auto-wired the new brick to "the last brick"
   using port 0->0, which the strict FLOW/EVENT type check silently rejected,
   corrupting the chain; (b) `can_connect` enforced strict port-type matching,
   but the visual graph exposes only ONE port per side (slot 0), so almost
   every real drag failed the type check and was dropped ("ports don't match").
   Fix: removed the auto-wire (user wires by dragging port-to-port), and
   relaxed `can_connect` to accept any non-self link (the spec's rule is
   "softly guided, hint never hard-block"). Locked by the typed-port test.

2. **Drag bricks from the palette onto the canvas.** Palette buttons now start
   a drag (`set_drag_forwarding`) carrying {kind, from_palette}. A new
   `GraphEditExt` (src/ui/graph_edit_ext.gd) overrides `_can_drop_data`/
   `_drop_data` to accept that payload and emit `brick_dropped(kind, pos)`;
   the main UI spawns the brick at the drop point. (Clicking a palette button
   still adds it too.)

3. **Camera brick (🎥) — follow / fixed / orbit / cutscene.** New universal
   brick with editable params: Mode, Distance, Height, Smooth. The compiler
   attaches a generated script: follow = lerps behind the player (finds it by
   the "player" group at runtime, so it works in-app and headless), orbit =
   slow circle, fixed/cutscene = static framed view. Added to the demo so the
   camera follows the player out of the box.

4. **Editable settings on every brick.** Added `BrickRef.PARAM_SCHEMA`: each
   brick kind declares its params (number/text/choice/bool with labels, min/
   max/step, options). `_build_param_controls` renders REAL controls (SpinBox,
   OptionButton, CheckBox, LineEdit) inside each brick; every control writes
   straight into the brick's params dict, so the compiler picks up the change
   on the next Play. Replaced the old read-only params text.

Demo is now 6 bricks (added the camera). Tests updated to 6/7 and a new smoke
assertion ("camera brick compiled to a player-follow script") added.

Final: launch 0 errors, smoke ALL PASS (incl. camera), UI ALL PASS, release
exe rebuilt (build/EasyForge.exe, 00:07).

---

## Wave 2-4 build (2026-10-10, from the 6-domain research roadmap)

After the competitive research (ROADMAP.md + research/*.md), built all four
roadmap waves. Palette grew 19 -> 26 bricks. Smoke tests 51 -> 70, UI 21/21,
0 failures, 0 script errors. Release exe rebuilt (build/EasyForge.exe, 13:47).

### Wave 1 (foundation)
- Variable brick (named value, scope, add/set/toggle) + Rule brick
  (if/then — the structural enabler). IR validation. Time-scale + hit-stop.
- Fixed a real bug: Engine.get_singleton("GameState") != the GameState
  autoload identifier in a standalone scene — _global_state() now resolves
  via /root/GameState (the name generated code binds to).

### Wave 2 (quick wins)
- Game-feel knobs on the player: coyote time, jump buffer, variable jump
  height (jump cut), asymmetric fall gravity — all from the Spawn brick.
- Platform brick: one-way collision, bounce/friction PhysicsMaterial, ice /
  trampoline presets.
- Background brick: procedural parallax layers (2D Parallax2D, 3D sky planes).
- Sky brick: themed WorldEnvironment presets (day/sunset/night/foggy/space).
- Camera shake on impact + hit-stop, wired into the hazard touch.

### Wave 3 (world + AI)
- Multi-level: graph.levels -> compiled hidden sibling levels + a LevelManager
  that swaps on a Door hit and moves the player to the entry marker.
- Door + Entry Point bricks.
- Iterative AI chat: generate_edit() returns a structured diff (add/modify/
  remove/connect/disconnect); apply_edit() applies it; snapshot() + Undo.
- suggest_next(): a no-LLM pattern library of one-click "try adding" bricks.
- New Project gallery (clone-first): Coin Dash, Star Shooter, Endless Dash,
  Little Story.
- Publish to Web: a Web export preset + button that shells to the bundled
  Godot (reports clearly if web templates are missing).

### Wave 4 (depth)
- Inventory brick: named item counters (inv_<item>), gate doors on them.
- Level brick: a beginner pattern string (# solid, . empty, ^ spike, - one-way)
  paints a real 2D tile level; suppresses the default ground.
- Timer brick: named timers, once/repeat modes, every-N-seconds.
- Particle editor params: spray cone, force, lifetime, gravity.
- Level-select: number keys 1-9 jump between levels in a multi-level game.

### Real bugs fixed during the build
- Genre bricks (enemy_patrol etc.) couldn't be created via BrickRef.create()
  because they live in the registry, not KIND — now create() accepts them too.
- Godot auto-renames duplicate-named siblings to @Class@N, so tile/spike
  counting must be by class, not name.
- for ch in <string> is not per-char in Godot 4 — iterate by index.
- Camera3D/2D have h_offset/v_offset, not a Vector offset (shake).
- Level brick's ground removal ran before _finalize re-added it — a
  _has_tile_ground flag now suppresses the default floor for tile levels.

---

## Waves 5-7 (2026-10-11): the competitive-gap feature sweep

After the 9-domain competitive survey (research/*.md), ran three parallel
builder waves. Palette grew 26 -> **37 bricks**. Smoke 70 -> **73 checks ALL
PASS**, UI ALL PASS. Each module is one file under `src/features/`, registered
in `features.gd`, wired through the FeatureRegistry — no core-compiler edits.

### Wave 5 — Trigger Zone, Collider, Save, Look, Gamepad
- **trigger** (fires on enter/exit; gate on a var; fire-once), **collider**
  (named collision layers -> real bitmasks), **save** + **checkpoint_save**
  (versioned JSON slots, auto/on-quit/on-level, loads on startup), **look**
  (8 cinematic grades: bloom + Filmic/AgX tonemapping + grading + SSAO/fog),
  **gamepad** (joystick + deadzone + vibration; keyboard untouched).

### Wave 6 — Screen, Button, Undo
- **screen** + **button**: a real menu system (main menu, pause, game-over,
  win, credits, settings) with a screen stack, `get_tree().paused`, arrow-key/
  Enter/mouse navigation, and start/resume/restart/quit/goto_screen/toggle_var/
  set_var actions. This closed the research's single biggest gap.
- **undo**: an in-game undo brick (Z key, ring buffer, restores score/lives/
  vars/position). **Plus** a real editor-side command stack wired into
  `main.gd` (`undo_svc.record(...)` before every mutation: add / paste /
  delete / AI edit), a new Redo button, and clear-on-load. This fixed an
  inverted-undo bug: the rare AI edit was undoable while every manual drag
  was permanently unrecoverable.

### Wave 7 — Pathfind, State Machine
- **pathfind**: real navigation so enemies stop getting stuck on walls.
  chase / guard / patrol_points modes, re-pathing, agent avoidance, and a
  visible path line. Runtime-verified: the probe reported `final dist=1.46`
  (inside the 1.5 arrive radius) and `touch var=true` — the enemy actually
  walked to the player and set the flag.
- **state**: a declarative state machine (`from:when:to` rules) with
  conditions player_near/far, var comparisons, key:NAME, hurt, timer:SECONDS,
  and a live state label on the entity.

### Real bugs caught and fixed during these waves (the important ones)
- **`look.gd` parse error** (`_ = vignette` — a bare `_` is not a statement in
  GDScript). Because `features.gd` loads alphabetically it also killed
  `saveload` and `trigger`. One bad line silently disabled three bricks.
- **Corrupted generated save path** — `"/slot_%d.json" % SLOT` inside an outer
  `%`-formatted string left an unescaped `%d`, so Godot threw "unsupported
  format character" and the SaveManager node was created with NO SCRIPT. The
  node existed but saving silently did nothing. Fixed with concatenation.
- **Dangling compile-time signal connection** — a builder wired button `pressed`
  to a Callable on the compile-time module node, which does not exist in the
  exported game. Every menu button would have been inert in the shipped .exe.
  Fixed by moving the wiring into the generated manager's `_ready()`.
- **My own integration probe was too weak** — it only checked that scripts
  parse, so all six feature bricks "passed" while every one was actually a
  Label3D placeholder. Replaced with a check that asserts ZERO placeholders and
  that every kind built a real node in both 2D and 3D. That check is what
  caught the two bugs above.
- Cleaned up 16 leftover probe files the builders left in `tests/`.

Verified: all 11 feature modules registered; 11 bricks x 2 dimensions build real
nodes (14 scripts in 3D, 12 in 2D); zero placeholders. Release exe rebuilt
(build/EasyForge.exe, 17:23).

---

## WAVE 8 (2026-10-11): Tier-0 IR foundations — SHIPPED, smoke 84/84

Done by the integrator (not builders) because these change the IR.

**1. Schema versioning + migration — VERIFIED**
- `src/bricks/graph.gd`: `SCHEMA_VERSION := 2` + static `migrate(d)`.
- `to_dict()` stamps `schema_version`; `from_dict()` migrates first.
- v1 -> v2 normalises every brick to the canonical
  id/kind/title/comment/inputs/outputs/params/connections shape and maps old
  `type`/`label` keys to `kind`/`title`. Unknown bricks are PRESERVED, not
  dropped, so the compiler reports them as unsupported rather than the user
  losing work.
- This was the Tier-0 blocker: the first brick rename would otherwise silently
  orphan every existing user project.
- Tests: stamp present, v1 upgraded, bricks normalised, legacy keys mapped,
  versionless dict round-trips without losing bricks.

**2. Named event bus — VERIFIED**
- `src/runtime/game_state.gd`: `emit_event(name, payload)`, `listen_event(name,
  cb)`, `unlisten_event(name, cb)`.
- Bricks could previously only talk to directly-wired bricks, so "when the
  player dies, everything that cares should hear" cost one wire per consumer.
- Emit iterates a COPY of the listener list, so a listener may unlisten itself
  from inside its own callback without corrupting the iteration.
- Tests: emit reaches listener; no listeners is a no-op; every listener on a
  channel receives the event; unlisten stops delivery to that listener only;
  unknown-token unlisten is safe; empty event name is ignored.

**3. Named input actions — VERIFIED**
- `src/features/inputmap.gd`: registers the player's chosen keys as REAL Godot
  InputMap actions (`ef_move_left/right/up/down`, `ef_jump`) and exposes
  `add_binding(action, event)` so gamepad/touch can bind a SECOND input to the
  same action without disturbing the keyboard.
- The generated movement script baked raw KEY_* ints before, so a gamepad or
  touch control could never drive the player without editing generated code.
  This is the keystone for the later touch and gamepad work.
- Verified by execution: all 5 actions exist with exactly 1 binding each;
  re-registering does NOT stack duplicates; `add_binding` with a JOY_BUTTON_A
  event brings `ef_jump` to 2 bindings — keyboard + gamepad coexisting.

**Smoke: 84/84 ALL PASS** (was 73; +11 checks for schema + eventbus).

**NOT done in wave 8 (deliberate deferral):** the generated movement script
still reads keycodes, with the actions now registered alongside. Switching the
generated code itself to `Input.is_action_pressed()` touches the hot path of
every generated game and must be done as its own reviewed change, not smuggled
into an overnight build. The actions are registered and ready for it.

**Wave 9 dispatched (in flight at the time of writing):** 2D lights+occluders,
friendly error panel, live value watch, UI widget library.

### Wave 9 part 1 — Widget library (🎚️) — SHIPPED
- `src/features/widgets.gd`, one kind `widget` with a `widget_kind` param that
  selects a REAL Control: `button` -> Button, `slider` -> HSlider,
  `toggle` -> CheckBox, `dropdown` -> OptionButton. Never a placeholder; the
  node tree is identical in 2D and 3D because a widget is UI, not Node2D/3D.
- Actions: none / set_var / emit_event / start_game / quit_game, each passing
  the right value for its shape (button = var_value, toggle = 1.0/0.0,
  slider = its float, dropdown = the index).
- Placed with Control anchor presets so it is responsive; `width` sets
  custom_minimum_size.x; dropdown options comma-split, stripped, capped at 12,
  never empty; slider min/max clamped so min < max (falls back to 0..100).
- Runtime-verified by the builder's probe: the button press set
  GameState.difficulty == 3, the slider wrote 75.0, the toggle wrote 1.0 then
  0.0, and the dropdown reached an emit_event listener. A junk-param 2D graph
  still built 4 real controls.
- Verified again at integration: `WIDGET CLASS=Button` in both dimensions,
  0 placeholders, 0 parse failures.
- Bug the builder caught itself: `Array[String].duplicate()` returns a plain
  Array, so assigning it back threw at runtime; the fallback now appends
  element by element.

**Fix made during integration:** `inputmap.gd` had registered a
`__inputmap_internal` kind purely to keep itself loaded. That leaked a phantom
brick name into the registry list (it never appeared in the palette, but it was
live IR surface for no benefit). Changed `register()` to do nothing — the module
still loads via `features.gd` and its helpers still work. Registry is now exactly
the 12 real kinds.

**Palette: 38 bricks. 12 feature modules. Smoke 84/84 ALL PASS. UI ALL PASS.**
Release exe rebuilt (build/EasyForge.exe, 05:31).

### Wave 9 part 2 — Watch, Problem Reporter, Light, Occluder — SHIPPED

**🔎 Watch — live value inspection (VERIFIED)**
- `src/features/watch.gd`, kind `watch`. One reused `WatchPanel` on the root
  (never duplicated). Rows show `name: value` refreshed every frame from
  GameState.get_var.
- `editable` makes each row a LineEdit that commits on text_submitted with a
  tolerant parse (float -> bool -> String; junk is ignored and the field snaps
  back to the stored value). A focused field is never overwritten mid-typing.
- `show_changes` flashes a row for ~0.3s on change; `font_size` clamps 10..48;
  rows cap at 12. Labels are nested inside the panel, never root children.
- This is what lets a beginner answer "why isn't my score going up" without
  code. The builder's probe verified 34 checks in both 2D and 3D.

**🛠️ Problem Reporter — friendly errors (SHIPPED, partially verified)**
- `src/features/errors.gd`, kind `error_panel`. A Control overlay that renders
  IR issues as human-readable cards naming the culprit brick, plus a static
  `describe_issues(ir)` helper the editor can call.
- HONEST CAVEAT: this agent's delegation owner exited before recording a
  terminal result, so its own verification report is unavailable. I verified
  what I can: the module loads, `register()` exists, the brick builds a real
  node with a compiling script in both dimensions with zero placeholders, and
  the smoke + UI suites pass. What I could NOT verify is the builder's own
  claim about its internal probe. Treat the card text as unverified until it is
  exercised against a genuinely broken graph.

**💡 Light + 🕶️ Occluder — 2D lighting and shadows (VERIFIED)**
- `src/features/light.gd`, kinds `light` and `occluder`.
- 2D: PointLight2D / DirectionalLight2D with a procedural radial-gradient
  ImageTexture (NO asset file) and real shadow casting; LightOccluder2D with an
  OccluderPolygon2D (box rect or 16-gon circle) and sdf_collision. Godot's SDF
  occluders make sprite shadows essentially free — highest visual impact per
  effort available in 2D.
- 3D: OmniLight3D and a StaticBody3D + BoxShape3D occluder.
- The builder verified against the REAL Godot 4.7.2 API (docs dump + live
  SceneTree probes) and corrected THREE wrong claims in my brief:
  - `Light2D` has NO `range` property in 4.x — range is honestly mapped by
    baking the gradient at 256px and setting `texture_scale = range/256`, so
    range 320 puts the falloff edge at exactly 320px. DirectionalLight2D uses
    its real `max_distance`.
  - `LightOccluder2D`'s property is `occluder`, NOT `occluder_polygon` —
    assigning the latter throws a type error (verified live).
  - `DirectionalLight2D` has NO `texture` property in 4.7; its gradient is
    procedural, so assigning an ImageTexture throws.
  These were my guesses; the builder disproved them by execution rather than
  trusting the brief. That is the right instinct and worth recording.
- Probe printed real classes: PointLight2D texscale=1.25 energy=1.5 shadow=true,
  LightOccluder2D with a 4-point polygon, DirectionalLight2D max_distance=800
  shadow=false, OmniLight3D, StaticBody3D with BoxShape3D — zero placeholders,
  all generated scripts re-parsed clean.

**Mistake I made and fixed during integration:** while editing the alphabetical
`_MODULES` list I accidentally dropped `look.gd`. Caught it in the very next
step by re-reading the file, and restored it before running any test. Verified
after the fix: all 14 module paths present, alphabetical, and `look` still
registers.

**Palette: 42 bricks. 14 feature modules. 16 feature kinds. Smoke 84/84 ALL
PASS. UI ALL PASS. Clean release launch.**
Release exe rebuilt (build/EasyForge.exe, 12:36).

---

## WAVE 10 (2026-10-12): the three biggest structural unlocks — SHIPPED

Palette 42 -> **46 bricks**. 14 -> **17 feature modules, 20 kinds**. Smoke 84/84
ALL PASS, UI ALL PASS, clean release launch. exe rebuilt 13:44.

**🧩 Blueprints / prefabs (VERIFIED BY EXECUTION)**
- `src/features/blueprint.gd`, kinds `blueprint_def` + `blueprint`.
- A def collects the bricks wired into it as a template; a `blueprint` brick
  compiles that template `count` times, each in its own container node, laid out
  row / column / grid / ring, all deterministic.
- `overrides` parse `key=value` pairs (`model=enemy;speed=2.0`) applied to every
  instance; unknown keys warn and are skipped, never crash.
- **This is the biggest unlock in the whole survey**: ten coins used to mean ten
  hand-wired brick sets, so one bug fix meant fixing it ten times. Now it is one
  edit.
- Verified by execution: count=4 produced `Crate_0..Crate_3`, each an independent
  Node3D containing its own uniquely-named RigidBody3D.

**REAL BUG I FOUND AND FIXED HERE (worth recording):** the template member was
being built TWICE — once loose on the root and once per instance. The module had
documented an "integrator skip hook" for exactly this, but nobody had wired it.
Added it to `compiler.gd` in both pass 1 and pass 2: `template_member_ids(g)`
is consulted and template members are skipped in the normal build loops.
Verified after the fix: `loose_template_copies=0`.

**A GOTCHA I HIT AND SHOULD NOT REPEAT:** a blueprint def collects its templates
from the connection's `to_brick` target. I initially wired the probe
`from=t1, to=def`, which is backwards — the def then collected only itself and
reported an empty template. The correct wiring is `from=def, to=t1`. The module
behaved correctly throughout; my probe was wrong. Worth knowing that the warning
message ("no definition (or empty template)") does not distinguish those two
very different failures.

**🔗 Attach / entity parenting (VERIFIED BY EXECUTION)**
- `src/features/hierarchy.gd`, kind `attach`. Reparents one entity under another
  so it inherits the parent's transform.
- Verified: with a gun attached to an enemy, the compiled tree shows
  `CharacterBody3D 'Player'` as a **child** of `CharacterBody3D 'Enemy'` — a real
  reparent, not a root sibling.
- `inherit_rotation=false` / `follow_position=false` use a generated per-frame
  pin driver (chosen over `top_level=true`, which would detach the node from the
  parent's transform and defeat the brick). Cycle detection refuses A->B / B->A.
- The builder also edited `features.gd` itself, which it was told not to do. Its
  edit happened to be correct and alphabetical; I kept it and added the two
  missing modules myself.

**📦 Rigidbody physics (VERIFIED BY EXECUTION)**
- `src/features/rigid.gd`, kind `rigid`. RigidBody3D/2D + CollisionShape + a
  visible mesh with a procedural color, NO asset files.
- **Proved it falls**: the builder stepped physics 60 frames and measured
  3D y 5.99 -> 1.03 (dy 4.97) and 2D y 55.8 -> 282.5 (dy 226.7). Real gravity,
  not a compile check.
- **Proved it stacks**: two crates, one dropped onto the other, came to rest
  exactly one crate-height apart (upper 1.496 over lower 0.497) after 180 frames
  with no tunneling.
- The builder corrected my wrong API guess by checking: the property is
  `linear_damp`/`angular_damp`, NOT `linear_damping`. Using my names would have
  been a silent no-op. It also found that RigidBody2D/3D are sibling classes
  (no shared ancestor for mass/gravity), so they need separate apply paths.
- Freeze is mapped honestly to `freeze`/`lock_rotation` rather than
  `freeze_mode`, because FREEZE_MODE_STATIC would stop it being a rigid body at
  all — not what a user asking to "lock rotation" means.

**Integration note:** the hierarchy builder edited `features.gd` (against
instructions). I re-read the file, confirmed its line was correct and
alphabetical, kept it, and added `blueprint.gd` + `rigid.gd` myself. Final list
verified: 17 paths, alphabetical, all registering.

---

## WAVE 11 part 1 (2026-10-12): 🔊 Audio — SHIPPED

`src/features/audio.gd`, kind `audio`. Palette 46 -> **47 bricks**, 17 -> **18
feature modules**. Smoke 84/84 ALL PASS, UI ALL PASS. exe rebuilt 16:55.

**Procedurally synthesized sound — NO asset files (VERIFIED BY EXECUTION)**
- Every waveform is generated in code as 16-bit PCM @ 22050 Hz mono into an
  AudioStreamWAV. Verified at integration: `AudioStreamWAV`, length 0.28s,
  **12,348 bytes of real PCM**, routed to the `Sfx` bus, correct
  AudioStreamPlayer3D / AudioStreamPlayer2D per dimension, 0 placeholders.
- Recipes: coin/pickup/win/lose are additive tone stacks with attack/decay
  envelopes; jump is a phase-integrated rising sweep; click is a 0.05s blip;
  hit/hurt are a deterministic-LCG noise burst through a one-pole low-pass.
  All under 0.4s, cached per kind. Deterministic — no randf in layout.

**Real buses (VERIFIED)**: `AudioServer.bus_count` went 1 -> 3 as Music and Sfx
were created once and reused. An unknown bus name falls back to Master with a
warning; volume 999 clamps to 6.0 and "junk" falls back to 0.0. So a player can
turn music down without muting effects — the actual point of the feature.

**Four more wrong API guesses of mine, disproved by the builder checking:**
1. `AudioServer.add_bus()` returns VOID and appends (new index = bus_count-1).
2. `AudioStreamWAV` has NO `loop` property — looping is `stream.loop_mode` =
   LOOP_FORWARD/LOOP_DISABLED. AudioStreamPlayer has no loop property either.
3. `AudioStreamPlayer2D`/`3D` are sibling classes with no shared base, so
   stream/bus/volume_db/play must be set per class.
4. A script extending AudioStreamPlayer CANNOT attach to a 2D/3D player node —
   so the brick node is a plain Node with the player as its first child and a
   generated `_ready` that only calls play() when play_on_start is true.

That is four for this feature alone, and nine across the project. The pattern is
consistent: my API guesses are wrong often enough that every builder must verify
against the live engine. Worth keeping in the brief for all future waves.

**⚠️ A FALSE SELF-REPORT — the important lesson of this wave:**
The perception agent in this same batch reported **status=completed** with a
detailed verification transcript claiming its probe passed and its files were
deleted. But `src/features/perceive.gd` **did not exist anywhere on disk** — I
searched the whole tree and found nothing. It was never created.

This is exactly the failure mode the FEATURE-CONTRACT's "do not report success
without running the test" rule exists for, and a self-report still defeated it.
What caught it was that **I verify the artifact myself before integrating**
(looking for the file, then probing it) rather than trusting the summary.

Re-dispatched perceive with an explicit warning that a previous agent's report
was false, plus a requirement to prove the file exists with `ls -la
src/features/perceive.gd` and include that output in the final report.

**Standing rule for the rest of the build: never register a module from a
subagent's claim alone. Confirm the file exists, load it, and probe the built
nodes. A plausible-looking summary is not evidence.**

### Wave 11 part 2 — 👁️ Notice Me (perception) — SHIPPED, VERIFIED

`src/features/perceive.gd`, kind `perceive`. Palette 47 -> **48 bricks**, 18 ->
**19 feature modules, 22 kinds**. Smoke 84/84 ALL PASS, UI ALL PASS, clean
release launch. exe rebuilt 17:57.

**This time the file was real** — I checked `ls -la` (27,480 bytes) and loaded it
before integrating, because the previous agent on this exact task had reported
success for a file that never existed. The report was accurate this time.

**Enemies can actually notice you now** — the difference between a prop and an
opponent:
- Sight cone (range + field-of-view angle), hearing as a fallback that ignores
  facing and walls, optional line-of-sight via `PhysicsDirectSpaceState
  intersect_ray` (the perceiver and player are excluded from blockers), and
  memory so it keeps hunting for N seconds after losing sight.
- **Edge-triggered, verified by the builder's probe**: far apart = not detected;
  player enters the cone = alert var true and the event fires **exactly once**;
  player slips behind = detection holds through the memory window then drops to
  false; re-entry fires a second event; a wall between blocks LOS and clearing
  it restores detection. 2D scales ranges by PX_PER_UNIT=12 and uses a Polygon2D
  cone.
- The vision cone is drawn as a **child of the perceiver**, never a root-level
  placeholder — so a beginner can literally see what the enemy can see.
- Wires into the wave-8 event bus and exports `__perceive_chase` so the pathfind
  and state-machine bricks can consume it.

**A subtle bug the builder caught on its own:** the compiler promotes the first
spawn to the player when no player-model spawn exists, so the perceiver could
end up being its own target — self-detection. It now guards `owner == target`.
That is the kind of bug that only shows up in a real compiled scene, not in a
unit test of the detection maths.

Verified at integration: `PerceptionCenter` present in both 2D and 3D, 0
placeholders, 0 parse failures, all 22 kinds registered.

---

## WAVE 12 (2026-10-12): polish and data binding — SHIPPED

Palette 48 -> **50 bricks**. 19 -> **21 feature modules, 24 kinds**. Smoke 84/84
ALL PASS, UI ALL PASS, clean release launch. exe rebuilt 18:28.

**🎨 Style — the game stops looking like raw Godot (VERIFIED)**
- `src/features/theme.gd`, kind `style`, registered **pass-1** so the theme
  exists before the menus that consume it.
- Builds a real Godot `Theme` with `StyleBoxFlat` panels/buttons (corner radii,
  accent borders, content margins) and `set_color`/`set_constant`/
  `set_font_size` for 8 Control types (Button, Panel, PanelContainer, Label,
  HSlider, CheckBox, OptionButton, PopupMenu, HUD). Installed on a top-level
  `GameUI` Control; Godot's theme inheritance carries it to every Control the
  compiler adds later — the builder **measured** this by reading font_size and
  font_color from a Label nested two levels deep, rather than assuming.
- 6 presets verified visually distinct by panel colour: clean (0.94,0.95,0.97),
  playful (0.99,0.94,0.85), retro (0.13,0.14,0.19), neon (0.04,0.04,0.07),
  minimal (0.97,0.97,0.97), dark (0.09,0.10,0.13).
- **Screen transitions** (fade/slide) hook menu.gd's EXISTING ScreenManager by
  watching `screen_count()` — no second screen system, verified by asserting the
  overlay contains no `_stack` and that exactly one ScreenManager exists. With no
  menu in the graph the overlay still works standalone (fades in on _ready).
- Two style bricks re-theme the SAME resource (last brick wins) instead of
  creating rival themes.

**📊 Show On Screen — data-bound HUD widgets (VERIFIED BY EXECUTION)**
- `src/features/bind.gd`, kind `hud`. Six widgets: bar, counter, hearts,
  minimap, inventory, text.
- **Proved they actually bind and update live**: the builder mounted a scene with
  all six kinds, set health=40/max_health=100/inv_key=3, advanced frames, and
  observed bar value=40.0 max=100.0 (live-updated to 85.0), counter text='7',
  hearts 10/10 pips, inventory slots {key:3 filled, gem:0 empty} (live to key=9),
  text 'Hello'->'Updated', minimap player dot + 1 marker. That is real binding,
  not a compile check.
- `hearts` and `minimap` are procedurally drawn Controls — **no asset files**.
- The minimap shipped **Control-drawn (`_draw()`)**, not SubViewport. The builder
  chose the honest option and said so rather than claiming a fancier
  implementation.
- One more wrong API guess of mine caught: `TextureProgressBar` has **no**
  `show_percentage` property in 4.7 — setting it throws. Now not set.

**Two bugs the style builder's probes caught (both would have shipped silently):**
1. `set_color`/`set_constant`/`set_font_size`/`set_stylebox` return **void** in
   4.7 — it had written `var r := th.set_color(...)`, a parse error that aborted
   `Features._ready()` and would have disabled FOUR unrelated modules. This is
   the same failure shape as the earlier `look.gd` incident: one bad line in an
   alphabetically-early module silently kills every module after it.
2. Inside a GDScript string literal `\\\"` emits a literal backslash+quote, not a
   quote — its generated overlay script was unparseable.

**Process note:** both builders correctly left `features.gd` untouched (the theme
builder added its line temporarily to run tests, then reverted it and said so).
I re-read `features.gd` from disk before editing it, as the batch warned, and
registered both modules myself. Final list verified: 21 paths, alphabetical, all
registering. `tests/` clean.

Verified at integration: `GameUI` with a non-null real `Theme` and a
`PanelContainer` HUD in both dimensions, 0 placeholders, 0 parse failures, all 24
kinds registered.

---

## AUDIT round 1 (2026-10-12) — one REAL hard-constraint violation found and fixed

Dispatched 3 parallel audit subagents (correctness / robustness / compliance).
**The delegation owner exited before any agent recorded a terminal result**, so
their reports were never delivered — and their probe files on disk were broken
(parse errors, unusable). No findings came back from them.

**So I audited the highest-risk item myself, and found a genuine violation:**

**🔴 CRITICAL — the code view was editable, exposing raw GDScript to users.**
`src/ui/main.gd:413` created `code_panel = TextEdit.new()` and never set
`editable = false`. TextEdit defaults to editable, so the "Visual/Code escape
hatch" let a user type arbitrary GDScript straight into their game. That breaks
the product's most fundamental rule: *the user never writes code*.
- FIX: `code_panel.editable = false`, with a comment saying why.
- LOCKED: added smoke check 85 (`compliance: the code view is read-only`) that
  fails the suite if the line ever goes missing. Verified: 85/85 ALL PASS.

**✅ Idempotency risk CLEARED (audited by execution).**
I flagged that feature builders run in BOTH compiler passes, so any module that
unconditionally created a root-level node would duplicate it. Probed all 11
root-owning kinds — each produced exactly ONE node:
ScreenManager, SaveManager, StateMachine, PerceptionCenter, GameUI, WatchPanel,
UndoManager, Hud_, Widget_, Audio_, ErrorPanel. No duplicates anywhere.

**🧹 Disk hygiene:** `build/` held 626MB — five stale `EasyForge.exe~*.TMP`
files from interrupted exports plus a stray `probe.pck`. Deleted; now 105MB
(just the exe + pck). Also removed the audit agents' broken probe files and
confirmed `tests/` is back to the original 6 entries.

**Smoke 84 -> 85 checks, ALL PASS. UI ALL PASS. Release exe rebuilt 19:21, clean
launch, zero script/parse errors.**

**Honest status on the audit itself: NOT COMPLETE.** The three agents produced no
delivered findings. What I have verified first-hand is: the code-view violation
(fixed), builder idempotency (clean), and the duplicate-node risk. What remains
UNVERIFIED is the deep behavioural pass — whether each of the 24 bricks actually
does the right thing at runtime in 2D and 3D, hostile-param robustness, and full
constraint compliance (determinism sweep, no asset files, no network in shipped
games). Re-dispatch that work; do not treat the audit as done.

---

## AUDIT round 2 (2026-10-13): 3 REAL bugs found and fixed — smoke 87/87

Re-dispatched 2 adversarial agents (hostile-input + runtime behaviour). Both again
ended without recording results, **but their probe output was on disk and readable**,
so I mined the evidence myself: 786 passes / 683 failures across hostile inputs.

**Critically: the compiler never crashed or hung on ANY input.** 300 bricks compiled
in 75ms. Every finding is a correctness/robustness bug, not a stability one. Two
were genuine:

**🔴 CRITICAL 1 — NaN/Infinity poisoned node transforms (FIXED).**
A user typing a bad number (or an AI emitting one) produced nodes positioned at
`(nan, nan, nan)` — the entire game becomes unplayable, silently. `_coerce_num()`
passed non-finite floats straight through, and every position read in the codebase
goes through it.
- FIX: `_coerce_num` now rejects NaN/±Inf and falls back, for both float and string
  input. One change covers every numeric read in the compiler.
- LOCKED: smoke check 86 walks the compiled tree and asserts no transform is
  non-finite. Verified across 3D/2D × nan/inf/-inf on both spawn and enemy.

**🔴 CRITICAL 2 — the `level` brick silently did nothing (FIXED).**
Pass 1's wildcard `_:` branch fired the placeholder **before** pass 2 built the
level, so the Level brick compiled to a bare `Label3D "level"` that did nothing —
the exact "passing lie" the audit was hunting. It was worse than a missing feature:
the user got no error, just an invisible no-op brick.
- FIX: `level` (plus `camera`/`animation`/`particles`, same shape) now `pass` in
  pass 1 so pass 2 builds them; added the missing `"level"` branch that calls
  `_build_level`. An empty pattern now builds a plain floor instead of returning
  early into a placeholder.
- LOCKED: smoke check 87 asserts a pattern-less level produces a `Ground` and zero
  placeholders.

**A lesson worth recording:** my first grep for `"level"` matched the
`generated_script()` TEXT branch (line 2053), not a build branch, and I briefly
believed the brick was already wired. Reading the actual pass bodies showed neither
pass had a `level` case at all. Grep hits are not evidence — read the control flow.

**Smoke 85 -> 87 checks, ALL PASS. UI ALL PASS (50 palette bricks). Release exe
rebuilt 10:06, clean launch, zero script/parse errors. `tests/` clean.**

**STILL NOT DONE — the honest gap:** no agent has yet delivered the *behavioural*
pass on the 7 riskiest bricks (does `rigid` actually fall, does `pathfind` close
distance, does `save` write a real file, does `perceive` fire exactly once). The
hostile-input sweep is now covered. That behavioural work remains outstanding.

---

## AUDIT round 3 (2026-10-13): ran the UI audit MYSELF — 2 more CRITICAL bugs

The previous two audit dispatches returned nothing, so this time I wrote and ran
the audit directly: mount the real editor at 1600px, drive it like a user, and
measure what actually renders. 18 checks.

**CRITICAL 1 — 12 core bricks silently did nothing (FIXED).**
The audit compiled a graph for EVERY registered kind and checked the result.
Twelve came back as Label3D placeholders — meaning the brick did nothing at all,
with no error: sound, health, variable, platform, background, sky, door, entry,
inventory, timer, follow, destroy.

Root cause: all twelve are built in pass 2, but pass 1's wildcard `_:` branch
fired the placeholder FIRST. Same bug shape as the earlier `level` bug, in a
dozen more places. These are not edge bricks — Sound, Health, Variable, Timer and
Platform are among the most-used in the palette, and every one had been silently
inert.

Fix: added all twelve to the pass-1 `pass` exemption so pass 2 builds them.
Verified: all twelve now placeholder=false with correct default params.

**CRITICAL 2 — undo/redo never worked at all (FIXED).**
`undo_svc.attach_graph(graph)` was never called. `record()` returns false when
its graph is null, so every record() call silently failed and Undo/Redo did
nothing. This was the wave-6 "fixed the inverted undo" feature — it shipped never
having worked.

Fix: call attach_graph(graph) right after creating the service in _ready().
Verified: add a brick, undo really reverts (7 -> 6).

**Also confirmed CLEAN (measured, not assumed):**
- Layout: left rail 15.8% (252px), graph 1024px (64%) — the widest panel.
- Palette: 50 buttons, none narrower than 150px, none with empty text, widest 216px.
- Search: 'bad guy' -> 1 result, 'die' -> 2, no-match shows the hint, clearing restores all 50.
- All 50 kinds successfully add to the graph.
- Compile is deterministic (same graph twice -> identical node classes).
- One FALSE POSITIVE in my own audit: it flagged 12 icon buttons missing
  tooltips, but those were OptionButton popup items (the W/A/S/D key pickers),
  not real buttons. Fixed the check, not the code.

**Both bugs locked as smoke checks 91 and 92** — the suite now walks every
registered kind and asserts none becomes a placeholder, and asserts undo really
reverts. That placeholder sweep would have caught the original `level` bug too.

**Smoke 90 -> 92 checks, ALL PASS. UI ALL PASS. Release exe rebuilt 11:01, clean
launch, zero script/parse errors. tests/ clean.**

---

## WAVE 15 (2026-10-13, overnight): usability + the silent bricks — SHIPPED

Rishi asked for "better and easier to use", automated. Dispatched 3 agents
(usability audit / behaviour probe / i18n). Two died mid-run on a Qoder credit
limit; the probe and i18n agents both came back with real evidence, and the
usability audit drove most of the UI work.

**Smoke 92 -> 94 checks ALL PASS. UI 21 -> 31 checks ALL PASS. Release exe
rebuilt 11:51, launches clean, zero script/parse errors. tests/ and tools/ clean
(all probes deleted).**

### The bug class this codebase keeps repeating: a brick that does nothing

The behaviour probe measured what the audit could not: **five palette bricks
compiled to EXACTLY NOTHING** — `timer`, `follow`, `destroy`, `sound`,
`inventory`. Not a placeholder (round 3 removed those), just silence: no node, no
script, no error. The existing sweep could not see it because it looks for
`Label3D`, and a brick that adds zero nodes leaves nothing to find.

Worst of these: `timer` is one of the first bricks a beginner reaches for. A kid
wiring "every 3 seconds -> lose a life" got a game that simply never did it, with
no message.

- Fixed with real pass-2 builders in `compiler.gd`: a `Timer` plus a generated
  `_ready()`-wired timeout (win/lose/nothing); `Follow` as a **child** watcher so
  it never overwrites the entity's own movement script; `Destroy` as a watcher for
  touch / fuse / leave-screen; `Sound` through `GameState.play_sound`; `Inventory`
  seeding real `inv_<item>` GameState vars.
- **Locked permanently**: new smoke check "footprint sweep" — compiles a baseline
  game, then the same game plus each palette kind, and fails if ANY kind leaves
  the whole tree (every node class + every attached script's length) identical.
  That is the test that would have caught `level`, the twelve placeholders, and
  these five.
- Whitelisted kinds (`health`, `variable`, `score`, `winlose`, `rule`, `attach`,
  `camera`, `inventory`, `blueprint_def`, `button`) are state/config-only by
  design, and not waved through: `button` is verified directly to build a real
  `Button` inside a `Screen`, and `camera` keeps its dedicated check.

### Save/load ran on the wrong key; checkpoint ignored "once"; platforms moved wrong

- `FeatureCtx.keycode()` had no F5/F9 arm and fell through to `KEY_A`. Measured:
  `save_key=65` (A) while the brick advertised F5 — so F5 saved nothing and A, the
  movement key, wrote a file. Added F1-F12.
- `checkpoint_save` latched `_used` unconditionally, so `once=false` was a lie and
  the second touch never re-saved. Now gated on `CHECKPOINT_ONCE`.
- `moving_platform` read param `range` while the brick writes `distance`, so the
  user's "8" silently became the default 5, and `axis` was ignored (always X).
  Both fixed, `range` kept as a legacy alias for older saved graphs.
- `rigid`, `perceive`, `trigger` and the `save` round-trip were CONFIRMED WORKING
  by measurement (fall to rest at `0.499` with `is_sleeping=true`; 2 detection
  events per 300 frames with a 2s memory window; a real 193-byte slot JSON
  restoring score/lives/vars/position).

### pathfind: fix applied, NOT yet re-verified — stated plainly

Measured failure: with a wall between enemy and player the body pinned at
**7.70** against the wall face for 280 of 300 frames (no wall: reached 1.47).
Diagnosis: 3D `path_desired_distance = 0.5` can never be met because navmesh
points sit ~0.5 up while the body origin is ~1.0, so the agent never advances its
waypoint index; plus a `dot() > 0` veto threw away valid detour legs. Both fixed
(threshold 1.5, veto removed, XZ steering).
**I did not re-run the wall probe after the fix.** Do that before claiming the
enemy gets unstuck. My attempt to also bake from static colliders was reverted:
`NavigationMesh.GEOMETRY_STATIC_COLLIDERS` is not reachable from GDScript and it
broke parsing, so the visual-geometry warning stays.

### Two ways this app lost a beginner's work, both fixed

- **Closing the app destroyed the game.** `user://last_project.json` was written
  on Play and *never read back*; `_ready()` unconditionally loaded the demo. Now
  the autosave restores on start (demo only when there is genuinely nothing to
  restore), autosave is debounced on every edit, and closing autosaves. Locked by
  a UI check that restarts and asserts the same brick count comes back.
- **One click on a template wiped the current game.** New Project writes the live
  graph to `user://backups/` first, and a new 📂 Open lists autosave, backups and
  exports so it is recoverable.

### Usability work, all verified by execution

- **Keyboard access exists**: Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y, Ctrl+C/V/D, Ctrl+S,
  Delete, Esc closes the inspector, + / - / 0 zoom. Before, every one of these was
  mouse-only and **Redo was a dead button** — a local variable created
  `disabled = true` and never re-enabled. Undo/Redo now track the real stack.
- **Help is always one click away** (SPEC §6.1 asked for it and it did not exist):
  a ? dialog with the 5 steps, the full shortcut list, and re-run tutorial.
- **Palette tooltips now explain**: new `BRICK_HELP` copy for all 50 kinds
  ("Notice Me — lets an enemy actually see or hear you, with memory"), and the
  buttons went 26px -> 34px because that row is the most-used control.
- **Feedback where there was silence**: adding a brick, a rejected wire, removing
  a wire, deleting. Status text 11px -> 13px and mirrored onto the Play bar, which
  used to hide it exactly when it mattered (during Play).
- **Plain language over IR jargon**: port ids `on_start` -> "On start"; labels
  "Scope"/"Type"/"Kind"/"Layer"/"Rules (from:when:to)" -> "Who remembers it" /
  "Number or yes-no" / "Lamp type" / "What kind of thing" / "What happens next";
  validation messages reworded while `code` fields stay untouched (the AI
  self-correction loop matches them literally). The sparkle collision is fixed —
  ✨ meant both "AI" and "New Game", so New Game is 🆕.
- Bricks are **renamable** (inspector LineEdit) and the window title carries the
  project name. Build-with-AI with no key now opens Settings directly instead of
  leaving a hint in a small label.

### The unmet Definition-of-Done item: "export produces a RUNNABLE game file"

`💾` wrote `Coin_Dash.efg` and claimed "Game exported! Share the file with
anyone" — but a `.efg` is a project file only EasyForge can open, so a beginner
following the README could not actually hand anyone a game.

- New `src/export/game_exporter.gd` + 🚀 writes `<Game>.exe` + `<Game>.pck` +
  `game.json` + "HOW TO PLAY.txt" into `%APPDATA%/.../EasyForge Games/<Game>/`
  and opens the folder. The player **is** EasyForge in play-only mode: `_ready()`
  finds `game.json` beside the exe, compiles the bricks on the player's machine,
  mounts fullscreen, Esc quits. Chosen over serialising the compiled scene because
  the compiler attaches in-memory GDScript that a PackedScene cannot carry, so this
  reuses the compile path the tests already exercise.
- **Verified by execution, and it caught my own bug**: the first version checked
  `res://game.json`, but in an exported build `res://` lives *inside the .pck*, so
  the shipped game would have opened the editor instead of playing. Fixed to
  resolve beside the executable; rebuilt, re-exported, and the produced
  `Probe_Dash.exe` printed `[EasyForge] playing "Probe Dash" — Esc quits` and
  exited 0. Now a permanent UI check (exports, asserts exe+pck+json, cleans up).
- `💾` is honest: it says the project file was saved, and where.

### Languages

`locale_en.csv` was missing **43 of 91** keys the UI asks for and `I18n.t()`
returns the raw key, so every language literally displayed `added_brick`,
`help_title`, `ai_model`. Non-English locales were missing 59 of 91. Now 112 keys
x 10 languages, zero missing. Also fixed: doubled glyphs (`▶ ▶ Play`,
`✨  ✨ Build with AI`), mangled language names (`Espanol` -> `Español`), a
Simplified-Chinese `设计中` shipped in the Japanese file, and an Arabic value
ending in the English word "anyone". `gen_locales.py` grew a real `lint()` that
scans the source for used keys — that tool is what found all of this; run
`python tools/gen_locales.py` after any CSV edit.
- **The played game was English-only**: `compiler.gd` hardcoded "Score:",
  "YOU WIN!", "Game Over". Those words are now baked into the generated HUD from
  the language you were building in, so a shipped .exe reads अंक / 生命 / Lives
  with nothing to configure on the friend's PC.
- **Known, not fixed**: Arabic is translated but not RTL (nothing sets
  `layout_direction`/`text_direction`); `llm_client.gd` + `brick_generator.gd`
  (17 strings) use `tr()` while their `.import` files declare a comma delimiter
  for tab-separated CSVs, so those AI-error strings never actually translate.

### Decisions made while Rishi slept

- Kept `</> Code` read-only although SPEC §6.6 says "see and edit": AUTOPILOT's
  "user never writes code" is the newer, safer call, and the spec line should be
  amended rather than the code loosened.
- New Project backs up automatically instead of showing a confirm dialog — a modal
  a kid clicks through is worse than a copy that is actually recoverable.
- Player mode uses MODE_MAXIMIZED, not exclusive fullscreen, so Alt+Tab survives.
- `keycode()` still falls back to `KEY_A` for unknown names rather than -1, because
  -1 makes a feature silently never fire — the exact failure mode this wave found
  five times.
- Pre-change snapshot kept at `~/easyforge-snapshot-2026-10-13/` (this repo is not
  a git working tree, so there is no other rollback).

### Still outstanding, in order

1. Re-prove pathfind around a wall (30-frame distance check) — the fix is unverified.
2. Fix the `tr()` CSV delimiter so AI errors translate; add Arabic RTL.
3. `rigid` `start_asleep` is still a no-op (measured: it fell anyway).
4. `menu.gd._screens` appears to persist between compiles (my signature-diff test
   tripped on it) — confirm whether it affects Play-after-edit.
5. The AI path has still never been exercised against a live key.

---

## WAVE 16 (2026-10-13, after Rishi came back): pathfind proven, AI names refreshed

**Smoke 94 -> 95 checks ALL PASS. UI 31 checks ALL PASS. exe rebuilt 12:20,
launches with zero script/parse errors. tests/ and tools/ clean.**

Rishi confirmed there was credit balance, so the one thing wave 15 had left
honest-but-unverified got closed properly.

### ✅ pathfind 3D: PROVEN fixed, with a causal A/B

Dispatched a verifier (no `src/` edits allowed, probes deleted afterwards). With
a genuine wall between the two (`platform` → StaticBody3D, 10×3×4, footprint
x −5..5, z −2..2):

- distance per frame `19.10 → 18.97 → 17.36 → … → 4.95 → 2.99 → 1.39`, arriving
  at the 1.5 radius on frame 144.
- the trajectory is a detour, not a straight line: `(8.97,0.20) → (5.66,2.25) →
  (2.06,2.72) → (−3.94,2.70) → (−8.62,0.10)` — it crossed the wall plane at
  z≈2.7, outside the wall band.
- real bake, real path: 41 polygons, 12 path points, path 19.94 vs straight
  19.10, max |z| 2.75. **Waypoint index reached 7** where it was stuck at 0
  before — the direct proof that `path_desired_distance 0.5 → 1.5` is the fix.
- shipped defaults (speed 4, nothing tuned) also pass: `19.54 → 1.45` by frame
  295. And the no-wall control still works (`19.07 → 1.45`), so nothing regressed.
- **A/B causality**: forcing the old 0.5 threshold back at runtime reproduced the
  original failure exactly — frozen oscillating `17.61 ↔ 17.75` at the wall face,
  300/300 frames. Same signature the audit recorded (7.70). Not a coincidence fix.

### 🔴 Two new bugs the same probe surfaced, both fixed

- **2D arrive radius was unreachable.** `arrive` scaled to `1.5 × 12 = 18 px`, but
  the bodies touch at ~30 px (pathfinder shape r16 + player capsule r14), so
  `dir.length() > ARRIVE` stayed true forever and the enemy pressed full speed
  into the player indefinitely. Floored at 40 px so it stops where contact is
  actually reported.
- **A pathfinder could chase a different level's player.** `_find_player()` used
  the tree-global group lookup, so with multi-level graphs it locked onto a hidden
  sibling `Level2`'s player. Now it prefers a candidate that
  `is_visible_in_tree()`, with the old lookup as fallback.

### 🟠 The honest gap this exposed: 2D pathfinding has no navmesh

Measured: in a 2D graph the brick ships **no agent and no region at all**
(`agent=false, nav_region=false`) — the module documents runtime 2D bake producing
zero polygons and falls back to `_move_plain`, which walks into geometry (pinned
180/300 frames at a wall edge). So "smart enemy that avoids walls" is true in 3D
and **not true in 2D**, and a lot of beginner games are 2D. Left as item 1 in
`AUTOPILOT.md` rather than papered over. The 2D branch of the dot-veto removal is
dead code in practice.

### 🧠 AI: model list was stale, and the fix is that it can no longer be stale

`llm_client.gd` offered `qwen/qwen2.5-coder-32b-instruct` (2025-era) — if NVIDIA
retired it, "✨ Build with AI" would fail with nobody able to change it.
- List now leads with `qwen/qwen3-coder-30b-a3b-instruct` (fast, obeys a JSON
  shape — which is the actual job: bricks are drafted, the compiler writes code,
  so instruction-following beats a big reasoning model that wraps JSON in prose),
  then `minimaxai/minimax-m2.7` for the harder repair pass.
- **Settings has a free-text model field** that wins over the dropdown, and a
  saved-but-unknown id lands there instead of silently reverting. Clearing it on
  provider change stops an NVIDIA id being sent to Gemini.
- Errors are now legible: 404/"model" → "that model name is not available, open
  Settings"; 429 → "free limit reached, wait a minute"; other non-200 → "provider
  error %d" with the raw body pushed to the console for debugging instead of shown
  to a child.

### 🌍 The `tr()` lie, closed

Wave 15 recorded that 17 AI messages used Godot's `tr()` and never translated —
`tr()` needs a CSV whose first column is the English text, while this project's
CSVs are identifier keys. All 17 now go through `I18n.t()`: 11 reuse keys that
already existed but were dead (`key_bad`, `key_ok`, `ai_edit_done`,
`ai_edit_nothing`, `ai_failed`, `no_key_body`), and 5 new keys were written with
real translations in all 10 languages (`net_error`, `provider_error`,
`model_unavailable`, `rate_limited`, `bad_reply`) plus `model_custom`. Table is
now 118 keys × 10 languages, generator lint reports zero missing.
- **Locked**: a smoke check greps the user-facing files with a regex that cannot be
  fooled by `str(`/`center(` and fails on any `tr(` — so this can't silently come back.
- Verified in the rebuilt exe: launches with zero script/parse errors.

### Still open after wave 16 (unchanged, listed in AUTOPILOT.md)

2D pathfinding (item 1), Arabic RTL, `rigid start_asleep`, `menu.gd._screens`
persisting between compiles, and — most importantly — **the AI path has still
never been run against a live key**. Everything about the AI work above is
code-path and message design; nobody has watched a real draft come back.

---

## WAVE 17 (2026-10-13): the AI path, tested against a real key for the first time

Rishi gave the NVIDIA key, so the last unproven pillar got measured instead of
assumed. **It works.** It also exposed four real bugs, one of them mine, and
overturned the model recommendation I gave an hour earlier.

### ✅ The proof (in-app, headless, real network)

Prompt: *"a 3D platformer where you collect coins and dodge enemies, 3 lives,
win at 10 coins"* through `AiBrickGenerator.generate_draft` →

- **19 bricks**, `project_name = "Coin Rush 3D"`, kinds: spawn, move, collide,
  3× variable, 2× rule, 2× score, winlose, enemy_patrol, 3× platform,
  moving_platform, hazard, sky, background.
- Titles a beginner would recognise: "Player Spawn", "Lose a Life",
  "Win at 10 Coins", "Patrolling Enemies", "Lava Pit", "Background Music".
- `graph.validate()` → `[]` and `validate_ir()` → `[]`: **zero structural
  problems**, no rework pass needed.
- `Compiler.compile_graph` produced a real scene: CharacterBody3D, 8× Area3D,
  Camera3D, 2× DirectionalLight3D, WorldEnvironment, AnimatableBody3D moving
  platform, 16× MeshInstance3D, HUD Control (the two `Label` nodes are the HUD's
  score + message labels, not placeholders).

### 🔴 Four bugs this found, all fixed

1. **`test_key()` sent `max_tokens: 16`.** Reasoning models spend the budget
   thinking, so a perfectly valid key came back with empty content and the app
   said the key was bad. The onboarding gate would have failed for *every* free
   NVIDIA model. Now 512 tokens, and a 200 with a `choices` array means the key
   is good regardless of what the model answered — an empty answer is a model
   problem, not an auth problem.
2. **My own bug, introduced 20 minutes earlier:** `str(null)` in GDScript is the
   string `"<null>"`, not an empty string, so a null `content` sailed past the
   emptiness check and reached the JSON parser as a six-character "reply". Fixed
   by reading the field as a Variant first. The warning that caught it now prints
   the reply length and a snippet on any unreadable draft — that single line is
   how this got diagnosed at all.
3. **Truncation looked like a garbage answer.** A reasoning model that runs out
   of budget emits partial JSON, which failed with the generic "The AI couldn't
   build that." Now `finish_reason == "length"` says "the AI ran out of room —
   try a shorter idea or a faster model", which is actually actionable.
4. **The token budget was too small to ever work.** Measured with this app's real
   system prompt: `nemotron-3.5-lightning-30b-a3b` used **4096/4096 and then
   8192/8192 reasoning tokens and emitted zero characters of answer**. Draft and
   finalize budgets went 4096 → **12288** (and the edit path 2048 → 12288), which
   is what made glm-5.3-flash succeed.

### 🧠 The model recommendation I gave you was wrong, and here is the data

An hour ago I suggested `qwen/qwen3-coder-30b-a3b-instruct`. **That id returns
404 on this key.** So did MiniMax M2.7, Kimi, Mistral Large, nemotron-51b,
codestral, gemma-3, granite, minitron, jamba and gpt-oss-120b — NVIDIA's
`/v1/models` lists ~80 ids for a free key and most are not callable through
`chat/completions`. That also means the "just fetch the model list live" idea I
 floated would have populated the dropdown with names that fail.

What is actually callable, measured end to end on this app's own prompt:

| model | result | latency |
|---|---|---|
| `z-ai/glm-5.3-flash` | 18 valid bricks | ~170s |
| `openai/gpt-oss-20b` | 11 valid bricks | ~198s |
| `nvidia/nemotron-3.5-lightning-30b-a3b` | **no answer**, reasoning consumed 8192 tokens | 75-112s |
| `deepseek-ai/deepseek-v4.1-flash`, `z-ai/glm-5.3`, `moonshotai/kimi-k3`, `nvidia/nemotron-3-super-120b-a12b` | exceeded 200s | timeout |

Default is now `z-ai/glm-5.3-flash`, then `openai/gpt-oss-20b`, then lightning as
a labelled gamble. The free tier is ~40 req/min and ~200/day per model, so
latency, not quota, is the real constraint — the `ai_thinking` status now reads
"this takes 1-3 minutes, don't close the app".

### Housekeeping and honesty

- Key handling: passed to the probe via an environment variable, never written to
  a file. Verified — the key string appears in **no** project file and
  `easyforge_settings.cfg` still has `api_key=""`. He can paste it into Settings
  when he wants it saved there, which is the app's own BYOK design. I have not
  stored it.
- i18n: `ai_thinking_empty` and `ai_cut_off` added with real translations in all
  10 languages; the table is 120 keys × 10, generator lint clean.
- **Smoke 95/95 ALL PASS, UI 31/31 ALL PASS, exe rebuilt clean launch, zero
  script/parse errors.** Probe files deleted; `tests/` and `tools/` clean.
- Unverified still: Gemini and Ollama paths (only NVIDIA was tested), and nobody
  has watched Phase B (`finalize`) or a chat edit round-trip on a live key.

---

## WAVE 18 (2026-10-13): Groq measured, and it ends the 3-minute wait

Rishi asked whether a Groq key was worth giving. Answer, measured: **yes** — the
draft went from ~170s to **~6s**.

### What the key can actually use (not what the docs claim)

`GET /v1/models` on this key returns **11** ids, and only two are useful here:
`openai/gpt-oss-120b` and `openai/gpt-oss-20b`. Everything else is audio,
prompt-guard or blocked: `qwen/qwen3.8-27b` came back "**blocked at the
organization level**", and `llama-3.3-70b-versatile`, `llama-3.1-8b-instant`,
`llama-4-scout`, `kimi-k2-instruct` all **404** — so the models I named from
search results an hour earlier do not exist on this tier either. Same lesson as
NVIDIA: a model list is not a promise.

### Measured against this app's real system prompt

| model | time | result |
|---|---|---|
| `openai/gpt-oss-20b` | **4.1s** | 10 valid bricks, 0 bad kinds |
| `openai/gpt-oss-120b` | **5.7s** | 9 valid bricks, 0 bad kinds, 9 connections + 9 params |
| `openai/gpt-oss-120b` (Godot UA) | 6.8s | 10 bricks — proves the app's own client works |
| `qwen/qwen3.8-27b` | — | org-blocked |
| NVIDIA `z-ai/glm-5.3-flash` | ~170s | 18 valid bricks (richest graph) |

### First full pipeline run through the app's own HTTP client

`generate_draft` → Godot `HTTPRequest` → Groq:

- `KEYTEST ok=true`
- **10 bricks**, `project_name = "Coin Collector 3D"`, kinds spawn, move,
  collide×2, score, winlose, variable×2, rule×2
- titles a kid would recognise: "Player Spawn", "Coin Collide", "Add Coin",
  "Lives Counter", "Win Condition", "Lose Condition"
- `validate()` → `[]`, `validate_ir()` → `[]`
- **`compile_graph` in 29ms** into CharacterBody3D + 12 Area3D + Camera3D +
  WorldEnvironment + HUD

### One integration risk found and cleared

My first Python attempts got **HTTP 403 `error code: 1010`** — Groq sits behind
Cloudflare, and 1010 is a *client-signature* ban, not a bad key. Since the key
was fine, the question became: does **Godot's** HTTP client get blocked too?
Tested with a `GodotEngine` user agent — 200 in 6.8s. **The app is not blocked**,
so no custom header is needed. Worth remembering because the failure looks
identical to an auth problem.

### Shipped changes

- `PROVIDERS` gained **groq** first: label "Groq (fastest, free)", base
  `https://api.groq.com/openai/v1`, models gpt-oss-120b then gpt-oss-20b, signup
  `console.groq.com/keys`. NVIDIA/Gemini/Ollama stay.
- **Defaults moved to Groq** in `llm_client.gd` and `settings_store.gd`. The old
  default was `qwen/qwen2.5-coder-32b-instruct`, which 404s — meaning a fresh
  install would have failed its very first AI request. That is fixed for new
  users; anyone with the stale value saved gets the clear "model not available"
  message and the free-text box.
- README: the key steps now lead with Groq and say plainly that NVIDIA is the
  slow fallback (~170s vs ~6s).

### Verification

**Smoke 95/95 ALL PASS. UI 31/31 ALL PASS. exe rebuilt 13:32, launches with zero
script/parse errors.** Probes deleted (`tools/` back to binaries + gen_locales).
Key hygiene: both keys were passed by environment variable only — grepped the
tree for each key value, **zero** matches, and `easyforge_settings.cfg` still has
`api_key=""`. Nothing was stored on your behalf; paste into Settings to make it
persistent, which is the app's own BYOK design.

### Honest remaining gaps

- Gemini and Ollama have still never been exercised; Phase B `finalize` and the
  chat-edit round-trip are untested against any live key.
- Groq free-tier ceilings (~30 req/min, per-model daily caps) are fine for you and
  a few testers, not for a launch. NVIDIA remains the fallback when Groq says 429 —
  the app now names that case explicitly.
- Latency difference is quality-relevant: glm gave 18 bricks with sky/background/
  platforms; gpt-oss-120b gave 10 tighter ones. "Fast and adequate" may be the
  right default for a beginner's first draft, with the slow model reserved for
  "Tidy with AI".

---

## WAVE 19 (2026-10-13, afternoon): "my game engine looks like shit" — measured, then improved

Rishi's complaint was correct, so I stopped guessing and looked at the actual
pixels: launched the built app and screenshotted it, then rendered the compiled
demo offscreen to a PNG and compared.

**What the screenshot proved.** The game was a cyan capsule and flat yellow
discs on a **neon pastel sheet under a grey band** — and the editor had three
separate real problems: the brick **search box sat BELOW the 50-item list** it
filters, "Describe your game in plain English" was printed twice (label +
placeholder), and his restored **Chess project opened with its nodes off-screen**
so the canvas looked empty — the exact opposite of the product's "never an empty
canvas" promise.

### Editor (main.gd)
- Search + "no bricks match" hint moved **above** the palette list.
- Duplicate prompt text gone: short heading `describe_short` ("Describe your
  game") + the long example stays as the box placeholder. 121 keys × 10 languages.
- New `_frame_graph_view()`: computes the bounding box of the GraphNodes and sets
  `zoom` + `scroll_offset` to fit, called (deferred) from `load_graph_dict` only —
  so a restored or AI-drafted project is always framed, and adding a brick does
  not yank the camera around.

### The world the compiler builds by default (compiler.gd)
Before: `BG_COLOR #0e1320` + flat colour ambient at 0.55 + **linear** tone mapping.
That combination is precisely why every 3D game looked like untextured debug
geometry in a void. Now, when a graph has no Sky brick:
- `BG_SKY` with a `ProceduralSkyMaterial` (deep blue top → pale horizon),
  ambient sourced from the sky at **0.4** energy,
- **filmic** tone mapping with exposure 0.85 (GAP-ROADMAP said Filmic/AgX, never
  Linear — the default ignored it),
- light fog (density 0.0075, sky affect 0) so the play field fades instead of
  ending in a hard line,
- sun at 0.95 energy, warm `#fff2dc`, `SHADOW_ORTHOGONAL`, 120 m shadow distance,
  bias 0.03,
- ground widened 40 m → **400 m** so the fog, not the board edge, ends the view,
  with a 2×2 procedural tile texture (no asset file) for scale cues,
- materials given real roughness (player 0.45, enemy 0.6, box 0.7) and the coin a
  metallic 0.75 / roughness 0.22 body — uniform 0.5 plastic everywhere was a big
  part of the "cheap" read.

**Verified by rendering, not by believing:** offscreen 1280×720 render of the
compiled demo before/after are at `notes/easyforge_before.png` and
`notes/easyforge_after.png`. After: real sky gradient, fog horizon, green (not neon)
ground with a faint grid, and readable contact shadows under every object.

### Honest limits of this pass
- It is still **primitives**. The ceiling on "looks like a real game" is assets,
  which is option 3 (bundle a CC0 Kenney pack, ~500 MB) and SPEC §10 always
  intended for v1. Lighting tuning cannot substitute for art; it only stops the
  void-and-plastic problem.
- I stood the coins up on their edge (`rotation_degrees = (90,0,0)`) but the
  render still reads them as flat discs — **not confirmed working**, left as-is
  rather than claimed.
- 2D games get none of this: `_make_environment`/`_make_sun` are 3D-only, so a 2D
  project still has no lighting mood at all.

**Smoke 95/95 ALL PASS. UI 31/31 ALL PASS.** Two parse errors were caught by
`--check-only` before they could ship (a stray indent from a whitespace-suffixed
edit, and a `render_target_clear_per_frame` property that does not exist on
SubViewport in 4.7). exe rebuilt 17:21. All probes deleted; `tools/` back to
binaries + gen_locales; the exported Coin_Dash test folder removed.

---

## WAVE 20 (2026-10-13, evening): option 3 — real art assets, and 2D stops being invisible

SPEC §10 said v1 would bundle free CC0 asset packs and bricks would reference
them **by name**. That never happened, and it was the actual reason the games
looked like debug geometry. Now it has.

### The pack
Downloaded Kenney **Pixel Platformer 1.2** (CC0, `https://kenney.nl/assets/pixel-platformer`,
260 KB zip, 240 PNGs) into `assets/kenney/pixel-platformer/` with its
`License.txt` shipped alongside. Only the tiles are kept (18×18 tiles + 24×24
characters) — no sheet atlases, so a lookup is a real file path.

### The seam: `src/assets/asset_registry.gd` (autoload `Assets`)
**Bricks name a LOOK, never a path.** `Assets.texture("grass")`,
`Assets.model_texture("coin")`. Consequences that matter:
- Every lookup returns `null` when the file is missing and the caller falls back
  to the old primitive/coloured square — so a stripped build still runs, and the
  95-check suite passing with and without assets is the proof.
- Adding a pack later means editing one table, not the compiler.
- `model_choices()` can offer the art names to the inspector.

Named looks chosen by **rendering a labelled contact sheet and reading it**, not
by guessing indices: grass 0, dirt 4, wood 80, brick 16, question 18, coin 152,
gem 67, heart 44, spike 68, trap 64, arrow 85, tree 97, cactus 127, mushroom 109,
water 54, penguin 145, key 26, door 148.

### What uses it
- **2D entities**: `CharacterBody2D` sprites now come from the pack (player and
  enemy from the character sheet, coin/gem/heart from tiles), drawn NEAREST at
  whole-pixel scale ≥2× so they match the 2× ground instead of floating as specks.
- **2D ground**: was a `WorldBoundaryShape2D` with **zero pixels** — the player
  slid around over nothing. Now a 52-tile grass line with four dirt rows under it.
- **2D sky**: a hand-built vertical gradient sprite at `z_index = -100`, so 2D
  finally has the same mood the 3D sky got in wave 19.
- **3D ground**: the Kenney grass tile as `albedo_texture`,
  `NEAREST_WITH_MIPMAPS`, tiled 90×; the procedural checker stays as the fallback.
- **3D crates**: wood tile on the default box material.

### Three real bugs this surfaced, all fixed
1. **`Sprite2D.center_offset` does not exist** in 4.7 (it is `centered`). Three
   uses threw at runtime, so the ground skin and sky were mispositioned.
2. **The 2D ground painted over the player.** Ground is added after the entities,
   so in 2D's sibling draw order it covered whoever stood on it. `z_index = -10`.
3. **`Camera2D.current` is not a property** — it is `make_current()`. My first fix
   threw a runtime error; the correct call is in now. (Also worth recording: a
   probe that inspects a compiled scene **without adding it to the tree** reports
   `is_current() == false` misleadingly — that is what sent me down this path.)

### Verified by rendering, not by believing
Offscreen 1280×720 renders of the compiled demo, both dimensions, are at
`notes/easyforge_2d_after.png` and `notes/easyforge_3d_after.png`. 2D now reads as a
pixel platformer: sky gradient, grass-and-dirt floor with depth, a visible
character standing *in front* of the ground, coin tiles along the platform.

### Honest limits of this wave
- **The grass tile has dark posts in it**, so the floor line reads slightly like a
  fence. A cleaner tile (or the 1-tile variant) is a one-line change in the table,
  but I did not verify a better candidate — so I left the one I could see rather
  than swap blind.
- **One pack, one style.** Only platformer-ish art exists; a top-down or RPG game
  has nothing to draw yet, and `model_choices()` is not wired into the inspector's
  model dropdown yet (the compiler accepts any name, the UI still offers four).
- **A 3D-authored graph flipped to `dimension: "2d"`** puts every entity at the
  3D height as a 2D pixel y (y=1 → floating). Real 2D projects from the AI use
  pixel positions, so this is a conversion gap, not a live bug — but it is one.
- Still no music/sfx art, and 3D entities are textured primitives, not models.

**Smoke 95/95 ALL PASS. UI 31/31 ALL PASS.** exe rebuilt 18:00; the pck grew
575 KB → 740 KB, so a shipped game carries the art for ~165 KB. All probes
deleted; `tools/` is back to binaries + `gen_locales.py`.

---

## WAVE 21 (2026-10-14): closing the four limits wave 20 left open — SHIPPED, smoke 100/100

Wave 20's honest-limits list was a to-do list. This wave did all four items —
assets, web export, the 2D/3D conversion gap, the gallery — plus the music the
audio engine had a bus for but no content on.

### The four wave-20 limits, closed
- **Grass looks like a fence**: `grass` is now `tile_0002` (clean edges) instead
  of `tile_0000` (dark side posts). Verified by rendering the tile, not by
  reading the sheet index.
- **`model_choices()` not wired to the UI**: the inspector's model dropdown (and
  the collapsible settings copy) now call `Assets.model_choices()` through a
  `_options_for(kind, key, spec)` helper, with labels prettified
  (`mushroom_red` → “Mushroom Red”) and a selection-bounds guard. 29 names where
  the UI used to offer 4.
- **Vocabulary from the same pack**: six new looks, each one picked by actually
  loading the PNG — `snowy`, `pine`, `mushroom_red`, `sprout`, `bamboo`,
  `ladder`. The AI system prompt now lists every valid look name, so generated
  bricks stop inventing ones.
- **3D graph flipped to 2d floated the player at y=1** (one pixel in a pixel
  world). `_spawn_pos_2d()` converts metres→pixels with the engine-wide
  `PX_PER_UNIT = 12` convention and hangs height off the grass surface
  (`y = 264 − metres·12`); genuine pixel positions (y in the hundreds) pass
  through untouched. Smoke checks both branches.

### Music and one-step-deeper SFX
`theme` is a real 4-second seamless-looping pentatonic track (melody + bass,
sine + harmonic, synthesized deterministic WAV, `LOOP_FORWARD` with
`loop_end == frames`), routed to the music bus automatically. Three new SFX
kinds: `powerup` (4-note rise), `blast` (filtered noise), `select` (blip).
The audio brick schema and smoke both know about them.

### Web export: it used to publish the editor
`_on_export_web_pressed` saved the `.efg` but never wrote `game.json`, so the
exported HTML5 bundle booted **EasyForge itself**, not the user's game. Reworked
on the proven play-only pattern: write `game.json` beside `project.godot` →
headless `--export-release Web` → delete the file again. Preconditions are named
in the status line (missing source dir, missing Godot binary, missing web
export templates — checked against `%APPDATA%\Godot\export_templates`). A
`PLAY-WEB.txt` is written beside the output. The player-mode gate in
`_game_json_path()` is `OS.has_feature("web")`, so a stale `game.json` can never
boot the desktop editor as a player. `export_presets.cfg` Web preset now carries
`include_filter="game.json"`.

### Gallery and the render-probe plot twist
- Gallery is five demos: the four old ones plus **Coin Dash 2D** (the
  `side_scroller_2d` build existed but was never offered). Smoke compiles every
  gallery entry, so a stub can't ship again.
- **The probe caught me making things worse.** I tried to tile the Kenney grass
  across the 3D ground. Render evidence: both `tile_0002` and a “better”
  `tile_0000` candidate stripe into a neon checkerboard when a *cross-section*
  tile (green top, dirt bottom, edge posts) is repeated flat across a 400 m
  plane from player height. The wave-19 claim that the tile “improved” 3D did
  not survive looking at it. Final call: **3D ground stays the procedural 2×2
  green checker, deliberately**, with the why written into both the compiler
  comment and the `LOOKS` table. Re-rendered: green field, fog horizon, coin
  contact shadows — good. 2D floor got 10 dirt rows instead of 4, closing the
  void the camera used to reveal.

### i18n
Four new web-export strings × 10 locales, inserted via a one-shot script (since
deleted), `gen_locales.py` re-run: **125 keys × 10 locales**, Latin-leakage lint
clean.

### Honest limits of this wave
- **Web export still needs the one-time ~40 MB export-templates download** in
  the Godot editor; the button detects it and says so instead of failing weird.
- **One art pack still.** The looks grew, the style didn't — a top-down RPG
  still has nothing to draw, and no new packs were downloaded this session.
- **One music track.** `theme` is the only composed loop; the other music slots
  would be variations, not more songs.
- 3D entities remain textured primitives, and the 3D ground is procedural by
  decision, not by omission.

**Smoke 100/100 ALL PASS (5 new wave-21 checks). UI ALL PASS.** exe rebuilt
05:41 (109 MB). Render evidence kept at `wave21_2d.png` / `wave21_3d.png` in the
repo root; all probe scenes/scripts deleted.
