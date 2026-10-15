# EasyForge — Universal Engine Gap Roadmap (consolidated)

**Date:** 2026-10-11
**Method:** 9 parallel research agents surveyed Unity, Unreal, Godot 4.7, GameMaker,
Construct, GDevelop, RPG Maker, FMOD/Wwise and the closest no-code peers across 9
engine domains. Each feature was scored on beginner impact, effort (S/M/L), and fit
with our hard constraints: **Godot 4.7 official (no fork), deterministic
bricks(JSON)→GDScript compiler, user never writes raw code, local standalone, no
hosting, primitives + procedural assets, 16GB/RTX 3050.**

Source docs: `research/engine-architecture.md`, `physics-collision.md`, `audio-engine.md`,
`input-accessibility.md`, `ai-pathfinding-behavior.md`, `ui-menus.md`,
`tooling-debugging.md`, `save-persistence-networking.md`.

**The pattern across all 9 domains:** Godot 4.7 already has nearly every primitive.
Our gap is not engine capability — it's **packaging** (beginner-trustable presets over
raw node graphs) and **IR expressiveness** (what a brick graph can say at all). Almost
everything below is compiler/inspector work, not engine work.

---

## Tier 0 — IR foundations (do first; later items depend on these)

| # | Feature | Domain | Effort | Why first |
|---|---|---|---|---|
| 1 | **Schema versioning + migration** | architecture | M | `from_dict()` accepts any shape with no version field. The first brick rename or default change silently orphans every existing project. **Must ship before #2/#3 change the IR.** |
| 2 | **Real undo/redo (command stack)** | architecture | M | Coverage is *inverted* today: the rare AI edit is undoable, every manual drag and param tweak is permanently unrecoverable. No architectural risk. |
| 3 | **Named input actions (InputMap)** | input | M | The keystone. Gamepad, touch, runtime rebinding and multi-input all become cheap after it, near-impossible before. Users still pick keys from dropdowns. |
| 4 | **Event bus / named global signals** | architecture | M | "When the player dies, everything that cares should hear" currently costs a wire per consumer. Small compiler change, large expressiveness gain. Best effort-to-impact ratio in the survey. |

## Tier 1 — highest beginner impact per effort

| # | Feature | Domain | Effort | Note |
|---|---|---|---|---|
| 5 | **Screen/Menu system** (main menu, pause, settings, game-over, credits + screen-stack) | ui | M-L | The single biggest gap. Every world-class engine ships this; Godot beginners rebuild it by hand every project. |
| 6 | **Trigger zones** (Area2D/3D as signals) | physics | S | Highest impact-per-line in the survey. Pickups, win zones, damage triggers — a beginner's #2 ask after jumping. Pure signal, perfectly deterministic. |
| 7 | **2D lights + shadows** (Light2D + LightOccluder2D) | rendering | S | Highest visual impact per unit of effort in 2D. Godot's SDF occluders make sprite shadow-casting free and automatic. |
| 8 | **"Look" / post-processing preset** (one Environment resource) | rendering | S | Bundles bloom + tonemapping (**default Filmic/AgX, never Linear**) + color grading + optional SSAO/DOF. Pure data, deterministic, zero engine risk. Cheapest AAA-feel win available. |
| 9 | **Friendly error reporting + recovery UI** | tooling | S-M | Link each IR error to its brick, plain language, suggested fixes ("add a Win Condition brick"). Most machinery already exists. |
| 10 | **Live value inspection + stats panel** | tooling | S-M | Watch AND edit any Variable live. The one debug feature a no-code user intuitively understands. Highest value-per-effort in the tooling survey. |
| 11 | **Compiler-emitted save/load + slots + version stamp** | save | S-M | A genuine *advantage* over Unity/Unreal: the compiler knows every variable's schema, so saves auto-emit instead of hand-rolled. |
| 12 | **Auto-save + checkpoints + save-on-quit** | save | S | Kills the "lost all progress" rage-quit. Settings persistence via `user://settings.cfg` rides along (S). |
| 13 | **Widget library + responsive layout** | ui | S-M | Buttons/sliders/toggles/dropdowns + container nesting, anchor presets, 48px+ touch targets. Fixes today's fixed-pixel HUD; everything else in UI composes on it. |
| 14 | **Collision layers & masks** | physics | M | Declarative gameplay rules (bullets vs enemies vs pickups, friendly fire). Stops beginners needing logic bricks. Compiles to deterministic integer bitmasks. |

## Tier 2 — major unlocks (M–L)

| # | Feature | Domain | Effort | Note |
|---|---|---|---|---|
| 15 | **Blueprints (prefab/instancing + variants)** | architecture | L | Ten coins = ten hand-wired brick sets today. Fix a bug once instead of forty times. Highest unblocking power in the survey — unlocks project organization, lazy level loading, genre packs. |
| 16 | **Scene/node hierarchy** | architecture | L | `compile_graph()` flat-`add_child`s everything, so "the gun is attached to the enemy" is inexpressible. Prerequisite for #15 and streaming. |
| 17 | **NavMesh + Pathfinding brick** | ai | M | Fixes the #1 "enemy gets stuck" complaint. Godot 4.7 NavigationServer2D/3D + NavigationObstacle do the work. |
| 18 | **State Machine brick + blackboard memory** | ai | M | Guard/flee/return/boss-phases as child states. Upgrades Variable into an inspectable key-value store. |
| 19 | **Procedural UI: one "Screen" brick** | ui | M | Our *structural advantage* over Unity/Godot/RPG Maker — they all hand-author menus; a compiler can emit a fully styled, navigable, data-bound screen from one brick. |
| 20 | **Rigidbody dynamics as a body mode** | physics | M | Falling crates, dice, stacking — the biggest physics wow. Native RigidBody2D/3D, deterministic at fixed 60Hz. Pairs with #14. |
| 21 | **Gamepad support** (dead zones, vibration, hot-plug) | input | M | Needs #3. Godot 4.7's SDL 3 layer gives uniform naming, circular deadzones, vibration and `joy_connection_changed` for free. Most common device a beginner's players own. |
| 22 | **Audio buses + mixing** | audio | M | Music/SFX/UI routing + volume sliders + DSP presets. The deterministic foundation every other audio feature builds on. |
| 23 | **Hot-reload / live-edit** | tooling | M | Value changes apply live (GameMaker instant-apply model); structural changes via sub-second deterministic recompile + respawn. Kills the stop-play-restart tax. |
| 24 | **Perception brick** (sight cone, hearing, LOS, memory) | ai | S-M | Makes patrol→alert→chase→search readable and teaches cause-and-effect. Pairs with #18. |
| 25 | **Behavior Tree brick** | ai | M | Nested selector/sequence trees with decorators + reusable subtrees. LimboAI (MIT) is a reference implementation. |
| 26 | **Touch/mobile controls** | input | M | Godot 4.7's built-in VirtualJoystick (FIXED/DYNAMIC/FOLLOWING) + touch buttons + gestures. Without it our web export is desktop-only in practice. |
| 27 | **Multi-input + runtime rebinding UI** | input | S+M (given #3) | Pad just works alongside WASD; a generated Controls screen using InputMap add/erase with saved prefs. Game Accessibility Guidelines place remapping in the *Basic* tier — expected, not premium. |
| 28 | **Style/theme presets + screen transitions** | ui | S-M | One shared Theme resource (palette, fonts, rounded StyleBoxFlat, hover/press states) + fade/slide tweens. Cheapest jump from "default gray Godot" to a real game. |
| 29 | **Data-binding via GameState signals + HUD kit** | ui | S-M | Replaces per-frame-polling HUD with a health bar, inventory grid, minimap, quest log driven by signals. Makes the first magic moment (score goes up) robust. |
| 30 | **Particle upgrades** (gradients over lifetime, emission shapes) | rendering | M | Our Particles brick emits the *low end* of a very capable GPUParticles system. |
| 31 | **Camera composition** (SubViewport stack + visibility layers) | rendering | M | Unlocks split-screen, minimaps, security-cam and portal views. Foundational for anything beyond a single scrolling camera. |
| 32 | **Joints** (hinge, spring, slider, pin) | physics | M-L | Gateway to a whole physics-playground genre (swings, seesaws, chains, pistons). Build the simple four; skip 6DOF. |
| 33 | **Graphics Quality preset** | rendering | S | One beginner-facing choice mapping renderer + FXAA→MSAA→TAA + FSR scaling + vsync/max_fps. Makes the RTX 3050 target feel intentional. |
| 34 | **Event tracing / visual logging** | tooling | M | Compiler-injected brick-named execution log answering "why didn't X happen" with zero code exposure. |

## Tier 3 — genuine differentiators (post-v1, server-free)

- **Local split-screen / hotseat multiplayer** (save-networking, S-M) — the biggest "wow" needing *zero* networking. Compiler emits per-player input sets + shared-World2D viewports.
- **Replay via determinism** (M) — input recording + deterministic resimulation. Traditionally expert-only; *plausible here precisely because the compiler is deterministic*.
- **Local-first on-disk telemetry** (M) — opt-in, GDPR-clean, exported via the same share-files flow.
- **Documented `user://saves/` folder contract** (S) — so the user's own Steam/OneDrive/Ludusavi setup syncs saves. Zero code, zero hosting.
- **Pitch/volume randomization** (audio, S) — one-property brick that kills the repetitive-SFX amateur tell.
- **3D spatial audio** (audio, S-M) — pan + distance falloff + doppler on AudioStreamPlayer2D/3D. HRTF deferred (GDExtension, poor fit).
- **Loop points + seamless BGM** (audio, S) — cheapest music enabler.
- **Reverb zones + music ducking** (audio, S-M) — Area3D reverb + bus volume tweens.
- **AI debug visualization + arrive/wander steering** (ai, S) — state labels, path lines, vision cones.
- **Version control + history pane** (tooling, S) — free win: JSON projects are text, so git diffs/blame/merge just work. Add in-editor history + restore-to-version.
- **Asset dependency viewer** (tooling, S-M) — "this brick is used 14×; deleting breaks 3 levels."
- **Blend modes** (rendering, S) — curated 4-mode picker (additive glow, multiply shadow), NOT the full matrix.
- **Gravity zones** (physics, S-M) — one brick yields space levels, water-float, planet games.
- **Accessibility basics** (input, S-M) — hold-to-press windows, saved settings, subtitles, one-handed presets, auto screen-reader metadata via Godot's AccessibilityServer.

## Explicitly rejected — with reasons

| Rejected | Reason |
|---|---|
| Cloud crash dashboards, shipped-game analytics, real A/B testing | Need a backend + audience → violate the local-standalone stance |
| In-game embedded cloud sync with OAuth | Auth tokens in a shipped game = a backend relationship |
| Dedicated servers, matchmaking | Infrastructure the stance deliberately avoids |
| Line-stepping code breakpoints | Exposes GDScript → contradicts the no-code promise (brick-level pause/hit-counts is the feasible version) |
| Motion blur | **Not available in official Godot 4.7.** A faked version would violate the "deterministic, honest" feel |
| Visual Shader *authoring* brick | Authoring programmatically is genuinely hard and the riskiest item. Ship a **curated graph library** first |
| Raw shader code, full blend-mode matrix, raw SSAO/DOF params | GameMaker and Construct both prove handing beginners raw rendering knobs produces trial-and-error and abandonment. **Curated presets, not knobs.** |
| Steam/EOS integration | Third-party hosting is zero-ops, but Steam-gating exports tensions with "share files yourself". Revisit post-MVP |
| LAN multiplayer | Stance-compatible (no EasyForge servers) but scope-risky: firewall/UPNP flakiness + big QA surface. **First thing to honestly revisit after MVP**, as an opt-in beta template |
| Rollback netcode | L+ effort, narrow genre (1v1 fighters) only. A fighting-game template is the only sane scoping |
| Physics-state persistence (full) | Advanced. Honest scope is per-body transform+velocity for *tagged* bodies, not whole-space snapshots |
| Tiled/LDtk import | Contradicts the no-code, primitives-only positioning |

## Recommended sequencing

**Phase A (foundations, unblocks everything):** #1 schema versioning → #2 undo/redo → #3 named input actions → #4 event bus.
**Phase B (visible quality, low risk):** #6 triggers, #7 2D lights, #8 Look preset, #13 widgets, #33 quality preset, #28 themes.
**Phase C (the big gaps):** #5 screen/menu system, #9 error UI, #10 live inspection, #11–12 save system, #19 procedural Screen brick, #29 data-binding.
**Phase D (M–L unlocks):** #15 blueprints, #16 hierarchy, #17 pathfinding, #18 state machines, #20 rigidbodies, #21 gamepad, #22 audio buses, #23 hot-reload.
**Phase E (differentiators):** split-screen multiplayer, replays, local telemetry, save-folder contract.
