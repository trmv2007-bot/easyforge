# Visuals, Art & Polish — Gap Analysis

EasyForge ships strong *gameplay* bricks and a procedural-color aesthetic, but has **no
visual authoring surface** — no way to change how a game *looks* without leaving the app.
That is the single biggest polish gap. Features ordered by impact-per-effort.

## Top features

1. **One-Click Style & Palette Presets ("Look" system)** — a global visual theme
   (pixel-art / flat / neon / retro-arcade / soft-cartoon) + curated palette that
   recolors every brick, particle, background consistently. Maps to a global "Style"
   setting the compiler reads and injects into every generated node (base palette,
   texture filter Nearest vs Linear, outline/glow material macro, default font). No
   per-brick changes. **S-M effort, very high impact** — fastest "make it look good";
   removes color-coordination guesswork.

2. **Visual Particle Editor** — upgrade the existing Particles brick from presets to
   live-editable params (spray cone angle, emitter force min/max, size/color over
   lifetime, gravity, additive blending, one-shot vs looping) + a live preview pane.
   Godot's GPUParticles2D natively supports every parameter. **M effort, very high
   impact** — particles are the #1 "juice" signal.

3. **2D Lighting Brick** — real-time PointLight2D + DirectionalLight2D + LightOccluder2D
   + ambient CanvasModulate, plus type/color/energy/radius/shadows/flicker in the
   inspector. **M effort, high impact** — instant mood/depth; torches, glows, dark caves
   become trivial. Native Godot 2D lighting, cheap on a 3050.

4. **"Game Juice" Pack** — (a) Camera FX: shake (duration+magnitude+axis), zoom punch,
   follow-lerp presets; (b) Screen transitions: fade/wipe/iris; (c) Light post-FX:
   vignette, color-grade tint, bloom via WorldEnvironment. Compiles to
   Tween/AnimationPlayer + WorldEnvironment + Camera2D. **M effort (each piece S),
   very high impact** — the cheapest perceived-quality jump from "student project" to
   "real game."

5. **Procedural Sprite & Character Library** — part-based generator (body base +
   accessory + palette swatches) outputting Godot-primitive-based sprites, plus a small
   bundled starter pack. **M-L effort (generator) / S (starter pack), high impact** —
   removes the "I have no art" blocker, the #1 blocker for non-artists.

## Strong runner-ups

6. **UI/Menu Designer** — drag-drop screens (Title/Pause/Game Over/HUD/Win) compiling to
   a Control scene + a ShowScreen brick. **L effort, high impact** — every finished game
   needs these screens.
7. **Parallax Background Layers** — parallax_factor on a Background/Sprite brick
   (0=fixed, <1=far) -> compiler offsets node by camera movement x factor. **S-M,
   medium-high** — cheap depth for side-scrollers.
8. **Day/Night & Weather** — DayNight brick (animate CanvasModulate + light energy) +
   Weather brick (particle preset + wind). **M, medium** — strong atmosphere, niche.
9. **Fonts & Text Styling** — font picker + size/color/outline/shadow; bundle a few
   open-licensed fonts. **S, medium.**
10. **Beginner Shaders** — curated allow-list of CanvasItem shader filters (outline,
    glow, wave, pixelate, CRT). **L, medium** — cool but risky; allow-list essential.

## Constraint check

- **No engine fork:** every feature uses stock Godot 4.7 nodes (GPUParticles2D,
  PointLight2D/DirectionalLight2D, WorldEnvironment, Camera2D, AnimationPlayer/Tween,
  Control, CanvasModulate, shaders).
- **Deterministic compiler:** all parameter-driven; the one design risk is the asset
  library — keep it Godot primitives + procedural color (no opaque binary imports).
- **16GB / RTX 3050:** 2D lights and particles are cheap; keep per-scene counts modest.
