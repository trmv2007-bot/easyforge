# EasyForge — Visuals, Art & Polish Gap Analysis

Research grounded in Construct 3, GDevelop, GameMaker, Buildbox, Core, Dreams, Stencyl, RPG Maker MZ, GB Studio, and Godot 4's own feature set. Each feature: what it is, how it maps to EasyForge's brick→compiler model, effort (S/M/L), beginner impact, and fit with constraints (Godot 4.7 official builds, deterministic JSON→GDScript compiler, primitives+procedural assets, no raw code).

---

## 1. Post-processing / effect library (bloom, vignette, scanlines, color grading)
- **What:** Construct 3 ships 80+ effects (tint, blur, scanlines, bulge, CRT, color replace); GDevelop bundles a full effect chain (Bloom, Vignette, CRT, Noise, Sepia, Godray, Tilt-shift, Chromatic aberration, Color Map) applied per-object, per-layer, or per-scene; GameMaker has FX layers (screen shake, tint, colour balance).
- **Mapping:** Compiler feature — the compiler already emits scenes, so it adds a `WorldEnvironment` + `Environment` resource with a curated shader library (Godot natively supports glow, adjustments: brightness/contrast/saturation, tonemapping, color-correction gradient). Exposed as a **"Look" preset dropdown** (Neon, Retro/CRT, Soft, Cinematic, Pixel) plus optional per-scene effect toggles. No new brick needed for the basic version; an optional "Effect" brick for runtime toggling (flash red on hit).
- **Effort:** S (Godot ships these natively; mostly data/JSON presets + compiler wiring).
- **Impact:** Very high — single biggest "looks professional" lever.
- **Fit:** Excellent — no fork needed, deterministic, RTX 3050 handles it.

## 2. Global "art style / theme" presets (pixel, flat, neon)
- **What:** AI tools (Rosebud, SpriteCook, AgentBrush) let you lock a project "theme" (pixel art / cel-shaded / flat) so all generated assets match; pixel-art tools enforce fixed palettes (PICO-8 16-color, Game Boy 4-shade, NES).
- **Mapping:** Project-level setting + new editor surface. A "Style" dropdown drives: (a) default color palette for all bricks, (b) pixel mode (nearest-neighbor filtering + integer viewport scaling), (c) default Look preset, (d) the system prompt EasyForge sends to its BYOK AI when drafting bricks. One switch restyles the whole game.
- **Effort:** S (mostly orchestration of existing settings + palette data).
- **Impact:** High — beginners don't know *why* their game looks bad; style presets fix coherence automatically.
- **Fit:** Excellent — palettes are pure data, fits deterministic compiler.

## 3. Pixel mode / render settings
- **What:** Crisp pixel art requires nearest-neighbor texture filtering, whole-number scaling, HDR 2D off/on control, disabled smoothing — engines like GB Studio enforce this; general engines make you find it in project settings.
- **Mapping:** Compiler/project feature — one "Pixel mode" toggle sets `texture_filter`, viewport stretch mode, and integer scaling in the exported project.
- **Effort:** S (a handful of project settings).
- **Impact:** Medium-high (matters hugely *if* pixel style chosen; cheap either way).
- **Fit:** Excellent.

## 4. Visual particle editor (parameters, not just presets)
- **What:** GDevelop's particle emitter exposes spray cone angle, gravity X/Y, particle size min/max, lifetime range, flow rate, rotation, start/end color, start/end opacity, rendering mode (circle/line/image); community tools like Carrot Particle Editor offer live GPU preview + JSON export.
- **Mapping:** Extend the existing **Particles brick** inspector with the full GDevelop-style parameter set (rate, spread/cone, gravity, size range, fade-in/out, color gradient, lifetime), plus live preview in the in-app Play mode. Godot's `GPUParticles2D/3D` supports all of these natively; the compiler just writes the ProcessMaterial.
- **Effort:** S/M (parameters map 1:1 to Godot particle properties; UI work in the inspector).
- **Impact:** High — presets look generic; tunable particles read as "crafted."
- **Fit:** Excellent — all native Godot particle material properties, fully deterministic.

## 5. Camera polish: shake, zoom pulse, follow-lerp presets
- **What:** GameMaker cameras offer lerp/damped follow, shake (strength/duration/decay), zoom control (xCamera marketplace asset formalizes shake/zoom/lerp as first-class). Godot `Camera2D` has position_smoothing_speed, limits, zoom built in; shake is ~10 lines.
- **Mapping:** Extend the existing **Camera brick** (4 modes) with: follow smoothing slider (maps to `position_smoothing_enabled`/`_speed`), zoom target + tween, and new event-style settings — shake(strength, duration) triggered by bricks (Collide/Hazard/Score). Compiler emits a small camera script; bricks get an optional "shake on trigger" field.
- **Effort:** S.
- **Impact:** High — "game juice"; hit-shake + zoom punch are the cheapest perceived-quality wins.
- **Fit:** Excellent — Camera2D is native; shake is deterministic math.

## 6. Screen transitions (fade, wipe, iris/circle)
- **What:** GDevelop's Flash & Transition Painter behavior does fade/wipe/circle transitions between scenes; tutorials build fade screens with tweens. Construct uses layouts + tweens.
- **Mapping:** New lightweight brick (or compiler feature): **Transition brick** with type (fade/wipe/iris), color, duration — emitted as a `CanvasLayer` ColorRect + `Tween` that plays on scene start and before scene change. Compiler hooks it into the scene manager it already emits for win/lose.
- **Effort:** S/M (Tween-based, ~1 GDScript helper).
- **Impact:** High — hides abrupt scene cuts; makes the game feel "finished."
- **Fit:** Excellent.

## 7. Menu / UI scaffolding: title screen, pause, game over, HUD
- **What:** Construct layouts double as menus; GDevelop templates ship title screens, pause menus (with volume ducking), HUDs; Stencyl has scene-level HUD drawing; RPG Maker ships 20 title screens. GDevelop's Tween behavior animates menu entrances (slide, scale-from-center, opacity) with easing curves.
- **Mapping:** New brick family: **TitleScreen, PauseMenu, GameOver, HUD** bricks — each a small config (title text, buttons: Start/Quit/Resume, which brick graph to launch) compiled to a Control-based scene. Compiler already manages win/lose state, so it owns scene switching. Tween presets (easeInOutQuad) applied to menu elements.
- **Effort:** M.
- **Impact:** Very high — a game without a title screen "feels like a prototype"; this is the #1 polish gap for beginners.
- **Fit:** Good — Control nodes + Tween are native; UI text is data-driven, compiler-stable.

## 8. Text/font styling
- **What:** Construct Text object with imported web fonts, BBCode formatting, and Sprite Fonts for pixel-perfect custom lettering; Godot supports dynamic fonts with size/outline/shadow.
- **Mapping:** Extend Score/UI-related bricks (or the HUD brick) with font presets (a handful of bundled OFL-licensed fonts), size, color, outline/shadow toggles; pixel style auto-selects nearest-neighbor rendering.
- **Effort:** S.
- **Impact:** Medium — typography is a big part of perceived polish.
- **Fit:** Good — bundle a few fonts in the export; deterministic.

## 9. Parallax background/foreground layers
- **What:** Construct layers scroll at different rates (parallax 0% for HUD, 50% for midground), individually scaled/rotated, sub-layers; GameMaker has ordered layer stacks.
- **Mapping:** Compiler feature — Camera brick (or new "Scenery" brick) emits `ParallaxBackground`/`Parallax2D` layers (far/near/foreground) with scroll factors; decorative only (never collision — a known Construct pitfall). Pairs with procedural gradient/sky backdrops.
- **Effort:** S.
- **Impact:** Medium-high — instant depth with primitives.
- **Fit:** Excellent — Parallax nodes are native 2D nodes.

## 10. Day–night cycle + weather
- **What:** GDevelop community extensions implement day/night (ambient light color/brightness by hour) plus "make it rain," dynamic water, 3D sky & sun; Buildbox added fog + weather via AI prompts ("turn fog on").
- **Mapping:** New **World brick**: time-of-day curve (day color → sunset → night) that lerps ambient tint/`CanvasModulate` color and light intensity; Weather brick as parameterized particle presets (rain, snow) + fog density. Compiler drives it from a clock variable the Timer brick can connect to.
- **Effort:** M (day-night S via CanvasModulate lerp; weather reuses particle system).
- **Impact:** Medium — strong atmosphere for platformers/survival genres.
- **Fit:** Good — CanvasModulate/particles native; deterministic via clock variable.

## 11. 2D lighting
- **What:** Godot natively has PointLight2D, DirectionalLight2D, LightOccluder2D shadows, CanvasModulate; most no-code engines don't expose this to beginners at all.
- **Mapping:** **Light brick** (point/directional, color, energy, radius) + automatic occluders from primitive collision shapes; "glow" per-object via modulate >1.0 when HDR 2D enabled. Compiler emits lights + LightOccluder polygon from the brick's shape.
- **Effort:** M (occluder generation from primitives is the tricky part).
- **Impact:** Medium-high for 3D and dark 2D games.
- **Fit:** Good — native nodes; watch perf on RTX 3050 (fine at these scene sizes).

## 12. 2D glow (neon look)
- **What:** Godot's WorldEnvironment glow works in 2D when background mode = Canvas and threshold lowered (or HDR 2D enabled since 4.2); neon aesthetics rely on it.
- **Mapping:** Part of Look presets ("Neon" preset sets glow on + low threshold + emissive-ish modulate); per-object "glow" toggle in the inspector.
- **Effort:** S (bundled with #1).
- **Impact:** High for neon/synthwave style.
- **Fit:** Good — documented 2D glow path in 4.7; performance cost acceptable.

## 13. Tilemap art + terrain auto-tiling
- **What:** Godot TileSet terrain system auto-connects tiles (47-tile match corners+sides); RPG Maker MZ ships 31 tilesets with autotile preview; Construct has a Tilemap Bar for painting; GB Studio scenes are painted from tilesets.
- **Mapping:** **Tile brick** (paint a region with a themed procedural tileset: grass/dirt/stone/water) — compiler generates a TileSet resource (procedural texture atlas with terrain bits) and a TileMapLayer. Terrain auto-connect means the beginner "paints ground" and edges fix themselves.
- **Effort:** M (procedural tileset atlas generation is real work).
- **Impact:** High for platformers — levels look built, not just floating primitives.
- **Fit:** Good — TileSet/TileMapLayer native; procedural textures fit the asset constraint.

## 14. Character/sprite composer (component-piece editor)
- **What:** RPG Maker's Character Generator combines hair/eyes/clothes/accessories with recolor palettes and offsets; GB Studio's Sprite Editor does frames/animation states/onion skin; AI generators (Rosebud, SpriteCook) produce sprite sheets from prompts with theme locking.
- **Mapping:** Two-tier answer. (a) **Bundled procedural character pack**: a library of palette-swappable primitive-based characters (a handful of archetypes × color palettes) that drop in as Spawn presets — cheap, on-brand with "Godot primitives." (b) Optional **BYOK AI sprite import**: EasyForge's existing AI-draft flow extended to generate a sprite sheet from text (Rosebud already exports Godot-ready PNG+JSON) that compiles into an AnimatedSprite2D — no in-app pixel editor needed.
- **Effort:** L for full editor; M for pack + import path.
- **Impact:** High — "I want *my* character to look like something" is the most common beginner art ask.
- **Fit:** Good — import path is deterministic (file in, compiler references it); avoid building an in-app pixel editor (violates no-code scope lightly, high effort).

## 15. Sprite sheet animation / frame cycling
- **What:** GB Studio sprite editor animation states; AI sprite-sheet generators carry frame timing + pivot in JSON; GameMaker/Construct import sprite strips.
- **Mapping:** Extend the **Animation brick** (spin/bob/pulse) with an optional "sprite frames" mode: a brick references an imported/generated sheet; compiler emits AnimatedSprite2D with frame timing + pivot from the JSON sidecar. For built-in primitives, keep procedural animation.
- **Effort:** M (import + compile path; editor reuse).
- **Impact:** Medium-high.
- **Fit:** Good.

## 16. UI/menu micro-polish: tweens, easing, squash-stretch
- **What:** GDevelop's Tween behavior animates position/scale/opacity/color with easing (linear, quad…expo, easeIn/Out/InOut, scale-from-center); menus slide in, coins fade out, buttons pop.
- **Mapping:** Compiler helper + brick setting: any UI/menu/popup element gets a "tween preset" (pop, slide-in, fade) that emits a Tween with a named easing; hit-flash on damage = modulate color tween. Reuse for transitions.
- **Effort:** S.
- **Impact:** Medium-high — this is literally "juice," the difference between static and alive.
- **Fit:** Excellent — Tween is native and deterministic.

## 17. Hit flash / damage feedback visuals
- **What:** Universal juice pattern (Stencyl effects: tint/blink actors; GameMaker flash + shake on hit).
- **Mapping:** Brick setting on Health/Hazard/Collide: "flash white + shake camera" on trigger — compiler emits modulate tween + camera shake call.
- **Effort:** S.
- **Impact:** High (perceived responsiveness).
- **Fit:** Excellent.

## 18. Asset library / smart assets
- **What:** Buildbox ships 20k+ smart assets with prebuilt logic; Core kitbashing from thousands of primitives/materials; GDevelop has an in-editor asset store; RPG Maker bundles a trove (tilesets, characters, title screens).
- **Mapping:** EasyForge's equivalent = a **curated built-in asset panel**: themed collections of primitive-composed sprites, tilesets, UI frames, sky palettes, particle presets — one click to add as a brick with sensible defaults ("smart asset" = brick with preconfigured settings). Skip a marketplace (local standalone games, no netcode).
- **Effort:** M (authoring content, not code).
- **Impact:** High — beginners choose, not configure.
- **Fit:** Good — pure data packs; keep them small and on-theme.

## 19. Beginner shaders / visual shader authoring
- **What:** Godot VisualShaders (node-graph shader authoring); Construct Effect Lab (live GLSL editing); Dreams' flexible aesthetic tools.
- **Mapping:** **Do not** build a shader editor. Instead ship ~10 curated visual shader effects as Look presets (outline, dissolve, water wobble, hologram) selectable per brick — beginners get the *results* without authoring. Constraint says user never writes code; a node graph is code-adjacent.
- **Effort:** M for the curated set.
- **Impact:** Medium (presets) vs high (editor) — but editor effort/fit is bad.
- **Fit:** Partial — results yes, authoring no.

## 20. 2D skeletal animation
- **What:** Godot supports Skeleton2D/Spine/DragonBones import; used for smooth character deformation.
- **Mapping:** Skip for v-next. EasyForge's procedural Animation brick + sprite-frame import covers beginner needs; skeletal rigging is an advanced art tool that fights the "no code, primitives" constraint.
- **Effort:** L.
- **Impact:** Low for the target beginner.
- **Fit:** Poor (authoring burden, asset pipeline complexity).

---

## Top 5 — ranked by impact-per-effort

1. **Look presets + pixel mode (post-processing pack)** — bloom/glow, vignette, scanlines/CRT, color grading, saturation/contrast, delivered as one-click style presets (Neon / Retro / Soft / Cinematic / Pixel). Godot ships every shader natively (Environment resource + glow in Canvas mode); it's compiler data, not code. Single biggest visual upgrade for the lowest effort — an S that transforms every exported game.
2. **Screen transitions + menu/HUD scaffolding** — Transition brick (fade/wipe/iris via Tween+ColorRect) plus TitleScreen/PauseMenu/GameOver/HUD bricks wired to the compiler's existing scene manager. An M-effort item that removes the "feels like a prototype" problem, the most common beginner complaint.
3. **Visual particle editor upgrade** — replace static presets with GDevelop-grade parameters (spray cone, gravity, lifetime, size range, color/opacity fade, flow) on the existing Particles brick, with live preview. S/M, maps 1:1 to GPUParticles ProcessMaterial, and tunable effects read as hand-crafted.
4. **Camera polish pack** — follow-lerp smoothing slider, zoom tween, and shake(strength, duration) triggers on Collide/Hazard/Score/WinLose. S-effort extensions to the existing Camera brick using native Camera2D smoothing; pure game-juice with the best effort ratio of anything on this list.
5. **Character/asset layer: procedural pack + BYOK AI sprite import** — a curated library of palette-swappable primitive characters/tilesets/UI frames as smart bricks, plus an optional AI-generated sprite-sheet import (PNG+JSON) compiled to AnimatedSprite2D. M/L effort but it answers the #1 art ask ("my game should have real characters") without building an in-app pixel editor.
