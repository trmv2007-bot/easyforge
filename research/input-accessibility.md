# EasyForge — Input, Controls & Accessibility Gap Analysis

**Date:** 2026-10-11
**Scope:** What world-class engines (Unity, Unreal, Godot 4.7, GameMaker, Construct 3) give beginners for input, controls, and accessibility that EasyForge lacks beyond its current remappable-keys + basic coyote/jump-buffer support.
**Constraints checked against every item:** Godot 4.7 official (no fork), deterministic bricks-to-GDScript compiler, user never writes raw code, local standalone, Windows desktop primary + web export.

## Current EasyForge state (verified in the repo at C:\Users\rishi\easyforge)

- Spawn brick exposes fixed key *choices* — Left: A/Left/J, Right: D/Right/L, Jump: Space/W/Up/K (src/bricks/brick.gd, PARAM_SCHEMA "spawn") — one key per action, from a hardcoded dropdown, not free rebinding.
- The compiler bakes those choices into the generated GDScript as integer constants (`const K_JUMP := %d`, `Input.is_key_pressed(K_JUMP)`) — src/compiler/compiler.gd (`_keycode()` maps a name string to a Godot `KEY_*` int; `_move_source()` emits `Input.is_key_pressed`).
- Rule brick "fire on key press" is likewise compiled to `Input.is_key_pressed(<int>)` for a fixed key set (Space/E/F/Enter/Shift) — src/compiler/compiler.gd `_rule_source()`.
- Game-feel already present: coyote time (0–0.3s), jump buffer (0–0.3s), jump cut, asymmetric fall gravity — all as number params on the Spawn brick. [verified: src/bricks/brick.gd:87-93, src/compiler/compiler.gd:357-410]
- No InputMap actions are generated (project.godot has no `input/` section), no gamepad/touch/haptics/gyro code exists anywhere in src/, no accessibility settings or screen-reader metadata in src/ or project.godot. [verified via grep]

That last point matters: because generated games read raw keycodes instead of InputMap actions, *every* engine input feature below (gamepad, touch, remapping-at-runtime, multi-device) is blocked at the architecture level. Unifying the compiler onto named InputMap actions is the single highest-leverage move and is item #1 below.

## Gap table

Each feature: one-liner · Effort (S/M/L) · Beginner impact (why a first-time game-maker cares) · Constraint fit vs. the five constraints above.

### 1. Named input actions as the compiler's foundation (action layer, not keycodes)
**One-liner:** Compile every brick input to named Godot InputMap actions (e.g. `move_left`, `jump`) with the Spawn brick's key choices as the action's event bindings, instead of baking `KEY_*` integers into scripts.
**Effort:** M — touch every emitted `_physics_process`, add an InputMap emit step to the compiler (deterministic map of param → events), keep output stable for tests.
**Beginner impact:** The foundation every other feature in this doc depends on; also makes "why doesn't my gamepad work?" and "how do I let players change keys?" answerable at all.
**Constraint fit:** Perfect — Godot InputMap is stock 4.7; the mapping param→events is deterministic; the user still picks keys from dropdowns, no raw code. This is the keystone.

### 2. Runtime action remapping (rebinding UI)
**One-liner:** An in-game "Controls" screen where the player clicks an action, presses a new key/gamepad button, and it takes effect immediately and persists.
**One-liner engine evidence:** Unity ships a reusable "Rebinding UI" sample built on `InputActionRebindingExtensions.PerformInteractiveRebinding` with conflict filtering and cancel paths; [17] Godot exposes the runtime primitives (`InputMap.action_add_event()/action_erase_events()`, `event_is_action()`); [3] Unreal explicitly lists "runtime control remapping" as a headline Enhanced Input feature; [19] the Game Accessibility Guidelines list "Allow controls to be remapped / reconfigured" as a Basic tier item. [27]
**Effort:** M (needs #1; UI can be a generated template scene + a small runtime script that calls `InputMap` mutation and saves to `user://`).
**Beginner impact:** The #1 accessibility ask from beginners who make games for friends ("my friend uses arrows, I use WASD"), and a visible "professional" feature in the final game's options menu.
**Constraint fit:** Stock Godot APIs, deterministic save of bindings per action, user wires nothing — drop-in generated "Controls" scene.

### 3. Gamepad support (dead zones, vibration, hot-plug)
**One-liner:** Generated games read gamepad axes with proper dead zones and button mappings, vibrate on hits/jumps, and handle controllers being plugged in or unplugged mid-session.
**Engine evidence:** Unity's Input System guarantees uniform control naming across platforms (buttonSouth is "A" on Xbox, "Cross" on PlayStation), ships deadzoned `StickControl` thumbsticks, dual-motor rumble via `Gamepad.SetMotorSpeeds(lowFreq, highFreq)` with pause/resume/reset, and `InputDeviceChange.Added/Removed` hot-plug events. [9][10][11] Godot 4.7 relies on SDL 3 for hundreds of controllers on Windows/macOS/Linux, provides `Input.get_vector()` with correct circular deadzones, `Input.start_joy_vibration(device, weak_motor, strong_motor, duration)`, `Input.vibrate_handheld()` on mobile, and the `joy_connection_changed` signal. [2][4] GameMaker has per-slot `gamepad_set_axis_deadzone`/`gamepad_set_vibration` and async "gamepad discovered/lost" system events. [22] Construct 3's Gamepad plugin exposes a `deadZone` property plus left/right vibration. [24][25]
**Effort:** M (needs #1; add gamepad button events to generated actions, dead-zone value already exposed, vibration helper in the generated runtime on Collide/Rule actions).
**Beginner impact:** Massive — beginners build on laptops but test with whatever controller is plugged in; "my brother has an Xbox pad" is the most common real-world device question. Dead zones fix stick drift that makes first games feel broken.
**Constraint fit:** Godot's SDL 3 layer is stock and deterministic; dead zone is a number param (already in the schema style); vibration = one generated call on existing Collide/Rule bricks.

### 4. Touch / mobile controls (virtual joystick, touch buttons, gestures)
**One-liner:** A virtual joystick + action buttons on-screen for phone play, plus tap/swipe/drag gestures — all configurable as bricks.
**Engine evidence:** Godot 4.7 *itself* added a built-in `VirtualJoystick` node with FIXED/DYNAMIC/FOLLOWING modes, a `deadzone_ratio`, a normalized `output` Vector2 and `is_pressed`, precisely because joysticks were "historically awkward to integrate" and only available via community addons. [1][6][29] Unity ships `OnScreenStick`/`OnScreenButton` components that feed the exact same action system as physical devices. [13] GameMaker's Gesture Events give Tap, Double Tap, Drag Start/End, Flick, Pinch, Rotate out of the editor, and its multi-touch tutorial is standard beginner material. [21][23] Construct 3's Touch object also feeds accelerometer motion. 
**Effort:** M (needs #1; a "Touch Controls" brick group that emits a `VirtualJoystick` node + `TouchScreenButton`s, shown only on touch-capable builds).
**Beginner impact:** EasyForge already ships a web export — without touch controls, every web-exported beginner game is unplayable on a phone. This is the difference between "runs on itch.io desktop" and "friends can play it on their phone".
**Constraint fit:** `VirtualJoystick` is a stock 4.7 node (the engine solved the awkwardness upstream — EasyForge inherits it for free); gestures map to the existing Rule brick's condition list; no code required.

### 5. Multi-input simultaneously (same action from keyboard + gamepad + touch)
**One-liner:** One action, many devices live at once: WASD until someone picks up a pad, and both keep working without the user configuring anything.
**Engine evidence:** Unity's default action set literally binds "Move" to both the left gamepad stick and WASD — "input through any of these bindings will perform the action" — with composites (2D Vector from four buttons, 1D axis, modifiers) and control schemes; [15] Godot's controller guide is titled "Supporting universal input" and shows keyboard + controller on the same action with no separate code paths (only mouse vs controller look needs split paths). [2]
**Effort:** S *given #1* (it's just multiple events per action, which InputMap models natively; S/L without it).
**Beginner impact:** This is the invisible quality bar: beginners with a pad plugged in expect the game to "just work" with it. Today an EasyForge game ignores the pad entirely even for movement.
**Constraint fit:** Trivially deterministic — the generated InputMap lists all events; no UI needed for the common case.

### 6. Advanced input buffering (attack buffer, multi-frame frame-perfect windows)
**One-liner:** Beyond jump: buffer any action (attack, dash, interact) inside a configurable window so early presses still register, and gate actions to frame-perfect windows (parry, just-dodge).
**Engine evidence:** Unreal's Enhanced Input guide models buffering explicitly — store the semantic request + timestamp + expiry, re-evaluate on state change (landing, cooldown end) — and pairs the request buffer with coyote time; [20] Unity ships Tap/Hold/SlowTap/MultiTap *Interactions* that recognize press-release patterns with per-interaction timing parameters; [12] GameMaker's double-tap has a tunable 0.16s window. [21]
**Effort:** M (extend the existing jump-buffer machinery in `_move_source()` into a generic "buffer window" number param on the Rule brick; frame-perfect windows = min/max age checks on the buffered request).
**Beginner impact:** Converts "my attack sometimes doesn't come out" — the most common beginner combat-feel bug — into a slider. Also the on-ramp to satisfying action games.
**Constraint fit:** Pure deterministic generated logic, numbers in the existing schema style; no raw code.

### 7. Local multiplayer split controls (P1 keyboard / P2 gamepad)
**One-liner:** One input scheme object per player, so "2-player on one keyboard" or "P1 pad / P2 keyboard" works from a dropdown instead of duplicated games.
**Engine evidence:** Unity's `PlayerInput` component pairs an InputUser to devices per player and is documented specifically for split-screen local co-op; [16] Construct 3 templates ship 2-player local multiplayer with split keyboard/touch; GameMaker supports multiple simultaneous gamepad slots (0-3 on Windows) with per-slot axis/button queries. [22]
**Effort:** L (per-player InputMap instances, device-pairing UI, camera/viewport handling — the biggest architectural item here).
**Beginner impact:** High aspiration value ("make a game we can play together") but rarely a first-project need; comes after single-player input quality.
**Constraint fit:** Fits Godot (multiple InputMaps, `Input.joy_connection_changed`), but the compiler needs a per-player concept it doesn't have — hence the effort.

### 8. Haptics (gamepad rumble + phone vibration)
**One-liner:** Rumble/vibrate feedback on impacts, pickups and deaths, as an action on existing Collide/Rule bricks.
**Engine evidence:** Unity documents dual-motor gamepad haptics (low-freq vs high-freq motors, global pause/resume/reset so a pause menu can silence everything); [10] Godot exposes `start_joy_vibration(device, weak, strong, duration)` and `vibrate_handheld(duration_ms, amplitude)` (Windows/Linux/macOS/iOS); [4] Construct 3's Gamepad plugin has left/right vibration; GameMaker has `gamepad_set_vibration` per slot. [22][25]
**Effort:** S (needs #1 so the vibration knows *which* device; otherwise S once devices are known — a one-line generated call per event).
**Beginner impact:** High juice-per-effort; vibration on a phone web-export build is the only haptic channel available there.
**Constraint fit:** Fully stock Godot calls; deterministic; a "Vibrate" action verb next to existing Rule actions like `hit_stop` fits the existing pattern exactly.

### 9. Gesture recognition (tap, double-tap, swipe, flick, hold)
**One-liner:** Recognized touch/mouse gestures exposed as Rule-brick conditions: tap, double-tap, swipe in a direction, hold N seconds.
**Engine evidence:** GameMaker's Gesture Events (Tap, Double Tap with tunable window, Drag, Flick, Pinch, Rotate) are editor-level, no code; [21] Unity's Interactions layer gives Tap/Hold/SlowTap/MultiTap patterns on any binding; [12] Godot's docs point at `Input.parse_input_event()` as the way to synthesize action events (the documented gesture-injection pattern); [5] Unity's `Chorded Action` trigger in Unreal covers "A while holding B". [19]
**Effort:** M (a generated gesture-recognizer node whose output feeds named actions — deterministic timing params as numbers).
**Beginner impact:** Lets a beginner make Subway-Surfers-style or pinball-style phone games; today the only input vocabulary is "key X pressed".
**Constraint fit:** Deterministic thresholds; synthesized via `Input.parse_input_event()` so downstream bricks see plain actions — architecture stays clean.

### 10. Gyro / motion sensors
**One-liner:** Tilt-to-steer: read accelerometer/gyro on phones and joypad motion sensors, mapped to a movement axis.
**Engine evidence:** Unity treats sensors as InputDevices (Accelerometer, Gyroscope, GravitySensor, AttitudeSensor, LinearAccelerationSensor) on iOS/Android, with Unity Remote for editor testing; [14] Godot's Input singleton provides `get_gravity()`, `get_gyroscope()`, `get_joy_accelerometer(device)` and `is_joy_motion_sensors_enabled()`/calibration functions; [4] Construct's Touch object exposes the accelerometer.
**Effort:** M (needs #1; a "Tilt" move style with sensitivity/dead-zone params; editor-testable only on device or via Remote).
**Beginner impact:** Niche — mostly mobile tilt-maze games; lowest urgency of the input items, but cheap once actions exist.
**Constraint fit:** Stock APIs; desktop-primary EasyForge means this mostly serves the web/mobile export, where calibration UX is hard to no-code (hence M).

### 11. Input recording & playback
**One-liner:** Record a play session's inputs and replay them — for demos, attract mode, tutorial ghosts, and bug reports.
**Engine evidence:** Community tooling exists rather than engine primitives (bitwes/GodotInputRecorder records via `_input(event)` and plays back through `Input.parse_input_event()`); [26] Godot documents `Input.parse_input_event()` as the injection path; [5] Unreal offers "Injecting Input" in Enhanced Input. [19]
**Effort:** L (deterministic engine makes replay feasible, but needs a recording/playback UI, storage format, and frame-count sync).
**Beginner impact:** Moderate — great for testing and for "watch the demo" on a title screen, not a day-one must.
**Constraint fit:** A deterministic compiler means the replay is truly reproducible (same input events → same game), which is exactly the case where recording shines; fits, but later.

### 12. Input debugging / visualization
**One-liner:** A live overlay showing which actions are firing, their values, and which device they came from — for the user AND for support.
**Engine evidence:** Unreal ships `showdebug enhancedinput` (and `showdebug devices`) console commands that display live action/axis mappings; [19] Unity's Input Debugger window shows devices and bindings live. 
**Effort:** M (generated debug overlay node toggled by a project setting; the compiler already knows every action).
**Beginner impact:** Real but indirect — turns "my controls don't work" support tickets into a screenshot; also a teaching aid showing the action layer.
**Constraint fit:** A generated overlay scene is deterministic and optional; no constraint risk. Medium priority because the compiler itself can now *validate* inputs at build time (e.g. warn "no gamepad binding on jump") once #1 lands.

### 13. Accessibility suite (colorblind modes, subtitles, screen reader, one-handed play, assist options)
**One-liner:** A generated Accessibility settings screen: colorblind palettes for sprite/UI colors, subtitle size/background options, hold-to-press instead of tap, auto-aim/assist toggles, adjustable speed, one-handed control layouts, and screen-reader metadata on generated menus.
**Engine evidence:** Unity 6 ships a native Accessibility module with screen-reader support across Narrator (Windows), VoiceOver (iOS/macOS), TalkBack (Android), navigable interfaces, and an `AccessibilitySettings` API that reads device font-scale/bold/closed-captions preferences; [18] Godot automatically enables screen-reader support (AccessKit-based AccessibilityServer with live-region/announcement APIs) when a screen reader is detected, with an `accessibility/general/accessibility_support` project setting; [7][8] the Game Accessibility Guidelines put remapping, simple control alternatives, saved settings and assist modes at the **Basic** tier; [27] the Xbox guidelines codify text display, subtitles and communication alternatives. [28]
**Effort:** L overall, but decomposes — subtitles + settings screen + saved prefs is M; colorblind palettes are M (a palette choice param that the compiler feeds into tintable sprites/UI); hold-to-press is S (window param on Rule conditions); one-handed layout is S given #2 (a preset binding set); screen-reader metadata is S (Godot auto-detects; needs generated UI nodes to carry names/labels — mostly free).
**Beginner impact:** Very high and under-appreciated: accessibility presets are the most-shared "wow" feature of no-code tools (GDevelop/Scratch users expect them), and Basic-tier items like remapping and saved settings are table stakes. [unverified on no-code-tool-expectations claim; the Basic-tier remapping/settings point is sourced from [27]] Also future-proofs against store/platform accessibility requirements for the web export.
**Constraint fit:** Godot's AccessibilityServer is stock and auto-detecting (nearly free for menus); subtitles/palettes are param-driven and deterministic; nothing needs raw code. Note: generated *game world* objects (not just menus) need labels/roles set at compile time — that's the M part.

### 14. Frame-perfect input windows & timing precision
**One-liner:** Configurable activation windows (parry frames, input-leniency age checks) and physics-tick-exact input sampling so frame-perfect mechanics are achievable and consistent.
**Engine evidence:** Unreal's buffering model timestamps every request on a consistent clock and re-evaluates on state changes, and is explicitly combined with coyote windows; [20] Unity's Interactions carry per-binding timing (duration, pressPoint, tapTime/tapDelay). [12]
**Effort:** S–M (generated `_physics_process` already runs on the physics tick; add per-action "window" number params and age checks in the buffer machinery from #6).
**Beginner impact:** The polish behind "my parry feels fair" — matters once a beginner moves past their first jump. Overlaps heavily with #6; ship together.
**Constraint fit:** Deterministic by construction; params only.

## What EasyForge already does right (keep)

- Coyote time + jump buffer as *visible number params* (0–0.3s) — many pro games ship them hardcoded; exposing them is genuinely beginner-friendly and matches the Unreal buffering model's knobs. [20]
- Key choices per action on the Spawn brick and a Rule brick that fires on key press — the right *concepts*; only the implementation (raw keycodes, fixed choices) limits them.
- Deterministic compile from bricks to GDScript — the exact property that makes recording/playback, multi-input unification, and build-time input validation (see #12) tractable.

## Top 5, ranked

Ranking weighs beginner impact × frequency-of-need ÷ effort, all filtered through the constraints.

1. **#1 Named input actions as the compiler foundation.** Effort M · Every other item in this document is cheap after it and nearly impossible before it; it's also what makes gamepad, touch, rebinding and multi-input one architecture instead of five hacks. Deterministic, stock Godot, no user code.
2. **#3 Gamepad support (dead zones + vibration + hot-plug).** Effort M · The most common real-world device a beginner's players have; Godot's SDL 3 layer hands over naming and dead zones for free; "plug in a controller and it works" is the single most visible input-quality jump.
3. **#4 Touch/mobile controls (VirtualJoystick, touch buttons, gestures).** Effort M · Godot 4.7 shipped `VirtualJoystick` *specifically* to kill this problem; without it the existing web export is desktop-only in practice. High reach, engine does the heavy lifting.
4. **#5 Multi-input simultaneously + #2 Runtime rebinding UI.** Effort S + M given #1 · Two views of the same win: universal input (pad just works) and a generated Controls screen (players fix it themselves). The Game Accessibility Guidelines put remapping in the Basic tier — it's expected, not premium. [27]
5. **#13 Accessibility suite, starting with the cheap basics: hold-to-press, saved settings, subtitles, one-handed preset, auto screen-reader metadata.** Effort S–M · Godot's AccessibilityServer auto-detects screen readers (near-free for generated menus), [7] most Basic-tier items are params the schema already knows how to express, [27] and the presets are the most demo-able feature in the whole doc. Defer colorblind palettes and full assist modes to a follow-up.

Deliberately deferred: local multiplayer split controls (#7, L effort, rare first-project need), input recording (#11, L), gyro (#10, niche), full debug overlay (#12, M and partly replaced by build-time input validation after #1).

## Sources

[1] https://godotengine.org/article/dev-snapshot-godot-4-7-dev-1 — Godot 4.7 dev 1 — VirtualJoystick highlight
[2] https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html — Godot 4.7 controllers/gamepads docs
[3] https://docs.godotengine.org/en/4.7/classes/class_inputmap.html — Godot InputMap class
[4] https://docs.godotengine.org/en/4.7/classes/class_input.html — Godot Input singleton (vibration, joypad, sensors)
[5] https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html — Godot Using InputEvent (parse_input_event)
[6] https://docs.godotengine.org/en/4.7/classes/class_virtualjoystick.html — Godot 4.7 VirtualJoystick class
[7] https://docs.godotengine.org/en/4.7/tutorials/ui/creating_applications.html — Godot screen reader integration docs
[8] https://docs.godotengine.org/en/4.7/classes/class_accessibilityserver.html — Godot AccessibilityServer
[9] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/Gamepad.html — Unity Input System — Gamepad support
[10] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.20/manual/gamepad-haptics.html — Unity Input System — Gamepad haptics
[11] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/Devices.html — Unity Input System — Devices (hot-plug)
[12] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/Interactions.html — Unity Input System — Interactions (tap/hold/multi-tap)
[13] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/OnScreen.html — Unity Input System — On-screen controls
[14] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/Sensors.html — Unity Input System — Sensors (gyro/accelerometer)
[15] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/ActionBindings.html — Unity Input System — Input bindings & composites
[16] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/manual/PlayerInput.html — Unity Input System — PlayerInput (local co-op)
[17] https://docs.unity3d.com/Packages/com.unity.inputsystem@1.19/api/UnityEngine.InputSystem.InputActionRebindingExtensions.RebindingOperation.html — Unity Input System — RebindingOperation
[18] https://docs.unity3d.com/6000.6/Documentation/Manual/accessibility/module-intro.html — Unity Accessibility module (screen readers)
[19] https://dev.epicgames.com/documentation/en-us/unreal-engine/enhanced-input-in-unreal-engine — Unreal Engine Enhanced Input docs
[20] https://adventuresincausality.com/unreal/unreal-enhanced-input/buffering — Unreal Enhanced Input buffering & coyote time
[21] https://manual.gamemaker.io/lts/en/The_Asset_Editors/Object_Properties/Gesture_Events.htm — GameMaker gesture events
[22] https://manual.gamemaker.io/lts/en/GameMaker_Language/GML_Reference/Game_Input/GamePad_Input/Gamepad_Input.htm — GameMaker gamepad input functions
[23] https://gamemaker.io/en/tutorials/multi-touch-joystick — GameMaker multi-touch & virtual joystick tutorial
[24] https://bugnet.io/blog/how-to-add-controller-support-construct-3 — Construct 3 controller support guide
[25] https://editor.construct.net/plugins/input/gamepad/c3runtime/IGamepadObjectType.d.ts — Construct 3 Gamepad scripting interface
[26] https://github.com/bitwes/GodotInputRecorder — Godot input recorder addon
[27] https://gameaccessibilityguidelines.com/full-list — Game Accessibility Guidelines full list
[28] https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/101 — Xbox accessibility guidelines 101
[29] https://codingquests.io/blog/godot-4-7-virtual-joystick-tutorial — Godot 4.7 VirtualJoystick tutorial
