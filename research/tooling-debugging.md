# EasyForge — Tooling, Debugging, Profiling & Live-Edit Gap Analysis

**Context:** EasyForge is a no-code Windows game maker. Bricks compile to Godot 4.7 games via a deterministic bricks→GDScript compiler. The user never writes raw code. Today the ONLY feedback surface is a status-bar message plus a `compile_failed` signal; IR validation catches duplicate ids, undefined vars, multi-player and no-goal. Projects are JSON. Hard constraints: Godot 4.7 official (no fork), deterministic compiler, no raw code, local standalone, 16GB RAM, RTX 3050.

This document surveys what world-class engines (Unity, Unreal, Godot itself, GameMaker) and the closest no-code peers (GDevelop, Construct) give beginners, evaluates each feature's honesty and feasibility when the user never writes raw code, and scores it against the constraints. Effort scale: **S** (days), **M** (1–3 weeks), **L** (a month+).

---

## Grounding facts (what the big engines actually ship)

- **Godot 4.7 (the target engine itself):** GDScript debugger, breakpoints (gutter-click or `breakpoint` keyword), step over/into, **Remote** scene tree (inspect AND change node parameters on the running game), live script reloading, live scene editing, a **Debugger** panel with **Monitors** (FPS, process time, physics, memory, draw calls via the `Performance` class, custom monitors), collider/nav-mesh visual debug drawing, and a **remote debugger** for other devices. ([Godot docs](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/overview_of_debugging_tools.html))
- **Unreal Engine:** Blueprint visual debugger with breakpoints ON NODES (right-click node → Add Breakpoint), **Watches** ("Watch this value" on any pin — floating value bubbles update live during play), execution-trace stack, debugger window listing breakpoints/watches/call stacks; plus `stat unit`/`stat fps`/`stat game`/`stat scenerendering`/`stat memory` HUD commands and Unreal Insights trace capture for frame-by-frame analysis. ([Blueprint Debugger](https://dev.epicgames.com/documentation/en-us/unreal-engine/blueprint-debugger-in-unreal-engine))
- **GameMaker:** full Debugger workspace — pause/step, breakpoints (F9, also on visual DnD actions), Watches (instance, variable, buffer, surfaces/textures), **real-time debug toggle** (variables update while running, not just when paused), **on-the-fly variable editing that takes effect instantly without recompiling**, memory/FPS graph view, input record & playback for regression tests, and a profiler (per-event/script/function call counts and average/absolute µs, top-down/bottom-up, GML vs Engine view). ([GameMaker docs](https://gamemaker.io/en/tutorials/debugger), [Profiler](https://manual.gamemaker.io/monthly/en/IDE_Tools/The_Debugger/The_Profiler.htm))
- **Unity:** code-line breakpoints via external editor attach (VS/VS Code), Locals/Watch/Call Stack windows, `Debug.Break()`, Profiler + Profile Analyzer, frame-time budget guidance (16.67ms at 60fps, p99 not averages). ([Unity docs](https://docs.unity3d.com/6000.0/Documentation/Manual/debugging-and-diagnostics.html))
- **GDevelop (closest no-code peer):** a **Debugger tab** that lists running scenes, live instances grouped by object, and **inspectable + editable global/scene/instance variables** — click a value to change it and watch the game respond; a **Profiler** that breaks time into Events / objects pre & post / visibility / render sections; 2D debug draw; pause execution. ([GDevelop wiki](https://wiki.gdevelop.io/gdevelop5/interface/debugger/))
- **Construct (closest browser peer):** event-sheet debugging that traces **which conditions passed and which actions ran** per event, with step-by-step event execution during play.
- **AI playtesting (2026 state of the art):** Ziva's playtest agent for **Godot** specifically (plain-English goals, real input, pass/fail with video, dozens of parallel instances); Razer QA Companion-AI (vision-based, zero integration, GDC 2026); nunu.ai; ManaMind (balance-focused). 35% of devs use automated playtesting. ([Ziva](https://ziva.sh/full-game-tester), [aiconjured](https://aiconjured.com/ai-game-dev-tools/playtesting-qa/))
- **Crash reporting:** Unreal ships CrashReportClient (minidump + call stack + system info, configurable upload endpoint); third parties (AccelByte ADT, GameNostic, Bugnet) add dedup, pre-crash video, dashboards. Built-ins are "enough for solo playtests" but lack dedup/dashboards.
- **A/B testing:** Unity's Game Overrides / GameAnalytics requires ~10,000 players per variant for validity — fundamentally a *shipped-game audience* feature, not a dev-time one.
- **VCS:** Unity ships Plastic SCM (Unity Version Control) with in-editor checkin/diff/compare; Unity Build Automation (CI/CD) triggers builds on VCS commit. Godot's own docs warn that binary/big files don't merge; JSON-only text projects are the exception — text merges cleanly, binary blobs never do. ([Unity VCS](https://unity.com/how-to/version-control-systems))

---

## Feature-by-feature assessment

### 1. Visual debugger + breakpoints
- **One-liner:** Pause the running game on a specific brick/branch and step through execution while watching state.
- **World-class:** Unreal Blueprint breakpoints on graph nodes + execution trace; GameMaker breakpoints on code AND visual DnD actions; Godot breakpoints + step over/into in the GDScript editor.
- **Honest feasibility for a no-code user:** This is the hardest sell. Code breakpoints presuppose reading a line of code and a call stack — concepts a no-code user doesn't have. BUT the honest reframing: EasyForge already has an IR (validated, with node ids). The compiler could emit breakpoint metadata mapped back to the **brick** the user placed. A "pause when this brick runs" feature is feasible without ever showing GDScript — it's a UI over IR positions. What should NOT be built: stepping line-by-line through generated GDScript (exposes code, defeats the no-code promise). Feasible no-code version: pause-on-brick, per-brick hit counts, and "which branches led here."
- **Effort:** L (compiler must carry source-mapping from brick → generated line; debugger protocol bridge from Godot's debugger into the editor UI).
- **Beginner impact:** Medium-high *only* if framed at brick level ("pause when the Score brick changes"). As a raw stepper: near zero.
- **Constraint fit:** Fits *with work* — Godot's own debugger provides the transport (debugger active by default in debug builds); the difficulty is the source-mapping, not the protocol. Deterministic compiler actually helps: stable brick→line maps.

### 2. Live value inspection (watch a Variable change in real time)
- **One-liner:** Watch (and edit) a variable's value on a live instance while the game runs.
- **World-class:** GameMaker watches + real-time toggle + instant-apply edits (no recompile); Unreal "Watch this value" floating bubbles; GDevelop editable variable tables per instance.
- **Honest feasibility:** THE best-fit feature for EasyForge and trivially feasible — Godot's Remote scene tree already exposes live node properties, and bricks already map variables to node properties. "Right-click your Score variable → Watch" is a panel listing `brick.health = 100`, updating live, editable (GameMaker's instant-apply model). No code shown, no breakpoints needed. Even a "scrub slider" for numeric variables (0–100) is a few hours of work on the Remote inspector.
- **Effort:** S–M.
- **Beginner impact:** Very high — this is THE debug tool a no-code user can understand: "my health dropped to 0, let me watch why."
- **Constraint fit:** Excellent — Remote tree is built into Godot 4.7 debug builds; deterministic brick→property mapping makes the UI trivial.

### 3. Performance profiler (frame time, draw calls, physics, memory)
- **One-liner:** See FPS/frame time, draw calls, physics time and memory broken down by section.
- **World-class:** Godot's own Debugger Monitors + Profiler (function-level); GameMaker per-event/script/function µs; Unity Profiler; Unreal `stat unit`/Insights.
- **Honest feasibility:** Godot gives frame time, physics, memory, draw calls for free via `Performance.get_monitor()`. The gap is only in presenting it and making it *actionable* ("your 200 sprites are causing 400 draw calls → batching suggestion"). Per-brick/function-level attribution requires instrumentation at compile time — the compiler can wrap each brick's generated function in a timing call (deterministic, no raw code exposed; the profiler shows brick names, not GDScript). A simplified "traffic light" HUD (green/amber/red FPS + draw calls + top-3 slowest bricks) covers 90% of beginner need.
- **Effort:** M for engine-monitor HUD; L for per-brick attribution (compiler instrumentation + UI).
- **Beginner impact:** High, but only in simplified form — raw frame graphs are expert tools.
- **Constraint fit:** Perfect — Godot 4.7 official provides all the data; nothing exotic needed; runs fine on RTX 3050.

### 4. In-editor game statistics (Monitors panel)
- **One-liner:** A live stats panel (FPS, memory, draw calls, object counts, physics bodies).
- **World-class:** Godot Monitor tab, GameMaker graph view (memory + FPS over time), Unreal stat commands.
- **Honest feasibility:** Essentially free — Godot already computes and exposes every monitor; EasyForge needs a pane that reads them. Also the home of **custom monitors**: compiler can auto-register each user Variable as a named monitor so "watch score" is just reading the stats panel.
- **Effort:** S.
- **Beginner impact:** Medium-high (as the always-on home of #2 and #3).
- **Constraint fit:** Excellent — pure `Performance` API usage, official Godot.

### 5. Friendly error reporting + recovery UI
- **One-liner:** Plain-English errors with a "Go to the problem brick" button and a one-click fix suggestion.
- **World-class:** GameMaker's error system pinpoints object/script and suggests the specific problem; Unreal's Blueprint compile feedback on nodes; Construct/GDevelop surface which condition failed.
- **Honest feasibility:** High — EasyForge already detects issues (duplicate ids, undefined vars, multi-player, no-goal). Today they land in a status bar; the delta is (a) structured error objects with brick IDs (already in the IR), (b) an error panel that links each issue to its brick, (c) plain-language phrasing, (d) suggested actions ("Add a goal: drag a Win Condition brick into the scene"), (e) dismissal/persistence. Recovery beyond that is UI work, not engine work. The one gap: RUNTIME errors (crash in the generated game) need a bridge back — Godot's error output + the source-mapping from #1 turns a GDScript runtime error into "Brick #42 threw an error at line X."
- **Effort:** S–M.
- **Beginner impact:** Very high — error messages are the #1 beginner pain point everywhere.
- **Constraint fit:** Excellent — mostly editor-side, deterministic IR already carries ids.

### 6. Hot-reload / live-edit (change a brick, see it update without restart)
- **One-liner:** Edit a brick while the game runs and watch it take effect immediately.
- **World-class:** Godot live scene editing + live script reloading (documented, changes reflected live, kept after stop); GameMaker instant variable apply; Unity Play-mode changes discarded by default (actually worse).
- **Honest feasibility:** Feasible but with a real caveat: Godot 4.4+ hot-reloads attached scripts on a display editor; **headless 4.4+ never re-instantiates the live node** (play/reload is display-bound) — EasyForge's harness is headless, so live-edit during automated tests won't propagate, but the user's editor is a display app so it works there. Practical middle ground: "apply value-only changes live" (variable values, property tweaks = GameMaker instant-apply) works everywhere; "apply structural changes live" (adding bricks, new wiring) = full recompile + quick scene reload rather than full project restart. Deterministic compiler + incremental recompile makes the reload sub-second for typical projects.
- **Effort:** M (live-apply for property changes + recompile-and-respawn loop, with an explicit "restart to apply structural changes" banner).
- **Beginner impact:** Very high — kills the #1 iteration friction ("change number → stop → play → wait").
- **Constraint fit:** Good — built on official Godot 4.7 live-reload; the headless caveat only affects the test harness, which can live with respawn-on-structural-change.

### 7. Visual logging / event tracing
- **One-liner:** A timeline of which bricks fired, in what order, with their values.
- **World-class:** Construct's event trace (which conditions passed, which actions ran); GameMaker call stack + debug messages; Unreal execution trace.
- **Honest feasibility:** High and unique — because every brick compiles through the deterministic compiler, the compiler can inject lightweight trace calls ("Brick `On Player Hit` fired; dealt 10 damage") into generated code at a global debug flag. Output is a readable event log, filterable by brick, live during play. This is strictly better than raw print debugging because it's brick-named, not line-named. Cost is the instrumentation pass; per-frame events should be sampled/throttled to avoid flooding.
- **Effort:** M.
- **Beginner impact:** High — "why didn't my door open?" answered by "the Key brick never fired because the Collision condition failed."
- **Constraint fit:** Good — pure compiler instrumentation, no engine fork; toggle off in release builds keeps output deterministic.

### 8. Crash reporting
- **One-liner:** Capture runtime crashes with context and surface them in-editor.
- **World-class:** Unreal CrashReportClient + third-party dedup/dashboards; Ziva/ADT pre-crash video.
- **Honest feasibility:** Medium-honest. For a LOCAL standalone tool the shipped-game crash dashboard is out of scope (no backend, 16GB local machine). What fits: (a) in-editor crash capture during play — Godot already prints the error; with source-mapping it becomes "Brick X crashed"; (b) a local crash log file with one-click "export report" for sharing; (c) "safe mode" relaunch — on corrupt project JSON, start with a recovery prompt instead of a stack trace. Crash DEDUP and dashboards: skip — requires backend, violates local standalone.
- **Effort:** S–M for local capture + recovery UI; L (and out of constraints) for remote reporting.
- **Beginner impact:** Medium-high locally ("it crashed but it told me which brick and saved my work").
- **Constraint fit:** Partial — local capture fits; remote dashboards violate the local-standalone constraint.

### 9. Automated playtesting & balance tools
- **One-liner:** AI agents play your game, find bugs, and report balance problems.
- **World-class:** Ziva (plain-English goals, Godot-native, pass/fail + video, parallel runs), Razer QA Companion-AI, nunu.ai, ManaMind (balance). GameMaker's record & playback input for regression.
- **Honest feasibility:** Medium-honest and high-leverage. EasyForge's smoke/UI harness already exists; extending it to "record input → replay" regression (GameMaker model) is S. Full AI playtesting is M–L: either integrate Ziva's Godot agent (it's literally built for Godot 4.2+) or build a BYOK AI loop (fits the BYOK AI product constraint!) that plays the game and reports. Balance analytics (win rates across N simulated runs) is a natural fit for a deterministic compiler: run the compiled game headlessly N times with scripted inputs, aggregate outcomes. This is arguably the single most differentiating feature — nobody in the no-code space has it well yet.
- **Effort:** M (record/replay + headless N-run balance stats) to L (BYOK AI playtester).
- **Beginner impact:** High — "my game beat you every time" becomes a report, not a vibe.
- **Constraint fit:** Good — headless runs use existing harness; BYOK AI already a product pillar; Ziva proves Godot 4.x compatibility.

### 10. Version control integration (git-friendliness of JSON projects)
- **One-liner:** Since projects are pure JSON text, git works perfectly — add friendly diff/commit/undo in-editor.
- **World-class:** Unity ships Plastic SCM in-editor (checkin, compare, undo); Unreal's binary .uasset projects famously CANNOT merge and need special plugins.
- **Honest feasibility:** EXCELLENT and almost free. JSON projects are text → clean line diffs, blame, real merges — the opposite of Unreal's nightmare. What's missing is only the *in-editor* surface: auto-save-to-repo prompts, a "history" pane (git log with restore-to-version), and one-click "try a change on a branch." The risk to engineer for: a single monolithic project.json means any two users editing different bricks conflict on the whole file — mitigate by splitting per-scene/per-brick files or a structural normalization (stable key ordering — the deterministic compiler already implies canonical serialization). That normalization is what turns git from "works" to "pleasant."
- **Effort:** S for basic integration (external git + history pane); M for project-file splitting + canonical serialization.
- **Beginner impact:** Medium-high — beginners rarely think about VCS until they lose work; auto-history + "undo yesterday" sells itself.
- **Constraint fit:** Excellent — JSON is the constraint; git is local, no backend.

### 11. Project diff & merge
- **One-liner:** See what changed between versions and merge two people's edits.
- **World-class:** Unity Plastic's compare revisions; json-git-style JSON merge for text projects; Unreal requires plugins for binary diff.
- **Honest feasibility:** Good — follows from #10. Text JSON diff is native git's job; EasyForge's value-add is a *semantic* diff ("Scene 2: moved Player 40px right; removed 2 bricks") rendered brick-level instead of line-level, plus a merge UI that resolves at brick granularity (both edited brick 42 → show both versions side by side). This is the payoff of deterministic, canonical JSON. Binary-asset merges: out of scope (same as everyone).
- **Effort:** M (semantic diff view + brick-level merge UI).
- **Beginner impact:** Medium (matters the moment a second user or a botched edit appears).
- **Constraint fit:** Excellent — text JSON; no binary merge problem.

### 12. Asset dependency viewers
- **One-liner:** "This sprite is used by 14 bricks; deleting it breaks 3 scenes."
- **World-class:** Unreal reference viewer, Unity asset usage counts.
- **Honest feasibility:** Medium — because everything is JSON, building the reference graph is a straightforward static analysis (brick → asset id → scenes using brick). UI: click an asset, see usages, click a usage to jump. Value is mostly in *deletion safety* ("can I remove this? no — 3 bricks use it").
- **Effort:** S–M.
- **Beginner impact:** Medium — prevents the beginner's #1 destructive mistake.
- **Constraint fit:** Excellent — pure JSON graph analysis, fully local.

### 13. Build pipeline & CI
- **One-liner:** One-click builds and automated builds on every change.
- **World-class:** Unity Build Automation (cloud CI on VCS commit, multi-platform, API).
- **Honest feasibility:** Medium-honest. The engine side is free: Godot exports headlessly (`godot --headless --export-release`), so "export exe" button = S. Cloud CI: violates local standalone (and EasyForge can't ship cloud). What fits: LOCAL build pipeline — export presets, a "build & smoke-test on every save" local job (uses the existing headless harness), build status in the status bar (already there — extend it), and export to itch/Steam-ready folder. Unreal/Unity-style cloud CI is a non-goal by constraint.
- **Effort:** S (one-click export), M (local build+smoke pipeline).
- **Beginner impact:** Medium-high for export S; the CI part is low for a solo beginner.
- **Constraint fit:** Good — local only, uses official Godot export templates.

### 14. Analytics dashboards
- **One-liner:** See how players interact with your shipped game.
- **World-class:** Unity Analytics (event browser, Data Explorer, dashboards), GameAnalytics.
- **Honest feasibility:** Honest LOW for EasyForge — dashboards require a backend and shipped players; the local-standalone constraint rules out the cloud version. The honest scoped version: LOCAL play-session analytics during development — the harness records "player died 12× on level 2, average run 45s, 80% never reached level 3" and shows it in a dev dashboard. That's actually the same data a beginner needs, with zero backend. Shipped-game analytics: out of scope, document as such.
- **Effort:** M for local session analytics dashboard; L + violates constraints for cloud.
- **Beginner impact:** Medium (as local dev analytics), near-zero as shipped telemetry (no players yet).
- **Constraint fit:** Local version fits; cloud version violates the local-standalone constraint.

### 15. A/B testing
- **One-liner:** Ship two variants of a brick value and see which performs better.
- **World-class:** Unity Game Overrides A/B (needs ~10,000 players per variant for validity).
- **Honest feasibility:** Honest LOW as shipped-game A/B — Unity's own docs say you need 10k players per variant, impossible for a local indie game made in EasyForge, and it needs a backend. The feasible cousin: LOCAL A/B via the headless harness — compile variant A and variant B (e.g., enemy speed 4 vs 6), run N automated playthroughs of each, compare win rates / average time. That's exactly the balance-tooling from #9, not true A/B. Present it honestly: "local balance simulator," not "A/B testing."
- **Effort:** S–M (as local simulation via #9's harness).
- **Beginner impact:** Low-medium — niche until a game actually has players.
- **Constraint fit:** Local simulation fits; real A/B needs a backend and an audience — violates constraints.

---

## Top 5 (ranked by beginner impact × feasibility ÷ effort)

1. **Live value inspection + in-editor stats panel (#2 + #4, S–M)** — watch AND edit any variable live on running instances; the one debug feature a no-code user intuitively understands, nearly free on Godot's Remote tree, zero code exposure. Highest value-per-effort in the entire survey.
2. **Friendly error reporting & recovery UI (#5, S–M)** — restructure existing IR errors into a linked error panel with plain language, "go to brick" buttons, suggested fixes, and crash-recovery on relaunch. Errors are the #1 beginner pain point and most of the machinery already exists.
3. **Hot-reload / live-edit (#6, M)** — apply value changes live (GameMaker instant-apply model), structural changes via sub-second deterministic recompile + respawn. Kills the stop-play-restart iteration tax that dominates beginner time.
4. **Simplified performance HUD + optional per-brick profiling (#3, M–L)** — traffic-light FPS/draw-calls/memory HUD built on Godot's free monitors, with compiler-instrumented "slowest bricks" attribution shown by brick name. Godot 4.7 provides all the data; the value is presentation and actionability.
5. **Event tracing + visual logging (#7, M)** — compiler-injected, brick-named execution log ("Brick `On Hit` fired, dealt 10") answering "why didn't X happen" without any code. Construct proves beginners value it; EasyForge's deterministic compiler makes it uniquely clean.

**Honorable mentions in order:** version control + history pane (#10, S — free win on JSON, ship early), automated playtesting/balance via harness (#9, M — highest differentiation), asset dependency viewer (#12, S–M — prevents destructive mistakes), project diff/merge (#11, M — follows from #10).

**Explicitly deprioritized with reasons:** cloud crash dashboards, shipped-game analytics, real A/B testing, cloud CI — all require a backend/audience and violate the local-standalone constraint; visual line-stepping breakpoints — exposes GDScript and contradicts the no-code promise (the feasible version is brick-level pause/hit-counts, folded into #1/#7).
