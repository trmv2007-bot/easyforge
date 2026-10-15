# EasyForge Physics & Collision Gap Research

**Scope:** What world-class engines (Godot 4.7, Unity 6, Unreal 5 / Chaos, GameMaker Studio 2) give beginners for physics & collision that a no-code Godot tool with only one-way/bounce/friction platforms + game-feel knobs lacks.
**Baseline in EasyForge today:** Platform brick (one-way collision, bounce, friction, ice/trampoline presets), game-feel knobs (coyote time, jump buffer, variable jump height, asymmetric fall gravity). No code, deterministic brick compiler, local, primitives-only assets.
**Constraint frame used for "constraint fit":** Godot 4.7 official (no fork), deterministic compiler (same bricks → same GDScript every time), no raw code exposed, standalone/local, primitive + procedural-color assets, 16GB / RTX 3050 budget.

Legend — Effort: S = days, M = 1–2 weeks, L = a month+ of compiler + UI work.

---

## 1. Rigidbody dynamics (2D & 3D)
**One-liner:** Bodies fully simulated by the engine — mass, forces/impulses, velocity, angular motion, damping — so crates fall, balls bounce and stack on their own (Godot `RigidBody2D`/`RigidBody3D`; Unity Rigidbody; UE5 Chaos; GameMaker fixtures with density/restitution).
- Effort: **M** (needs a "dynamic body" brick with mass/damping/gravity-scale sliders, plus sleeping/freeze modes to keep determinism)
- Beginner impact: **Very high** — the "wow" of physics games (Angry Birds, snowballs, dice) is one brick away.
- Constraint fit: **Good.** Pure project settings + nodes, deterministic. Watch: many awake bodies on a 3050 needs sleep/culling; keep per-scene body counts bounded.

## 2. Kinematic vs dynamic character controllers
**One-liner:** Unity exposes Body Type = Dynamic/Kinematic/Static; Godot's `CharacterBody2D`/`3D` (move_and_slide) is the beginner-friendly "I control it, physics still collides" body, vs RigidBody "physics controls it."
- Effort: **S** (a mode toggle on the player brick: scripted controller vs simulated body)
- Beginner impact: **High** — answers the #1 beginner confusion ("why can't I control my ball?") and enables moving platforms that carry the player.
- Constraint fit: **Excellent.** CharacterBody is the deterministic workhorse; EasyForge already compiles movement scripts.

## 3. Collision layers & masks
**One-liner:** 32 named layers per object; collision happens only when A's mask matches B's layer — lets beginners express "bullets hit enemies but not each other" declaratively (Godot, Unity layer collision matrix, UE collision channels/presets).
- Effort: **M** (needs a named-layer UI in the editor that the compiler maps to bitmask ints)
- Beginner impact: **High** — unlocks pickups, hitboxes, friendly fire rules without a single "if" node.
- Constraint fit: **Excellent.** Compiles to integer bitmasks; fully deterministic; zero runtime cost.

## 4. Shape variety — convex, concave, heightfields
**One-liner:** Godot offers box/sphere/capsule/cylinder primitives, convex hulls (Quickhull/V-HACD), concave trimesh (static only), and `HeightMapShape3D` for terrain; GameMaker has circle/box/capsule/polygon fixtures.
- Effort: **M** (auto-pick from primitive: box for blocks, circle for balls, capsule for characters; convex-from-mesh is a bonus)
- Beginner impact: **Medium-high** — a circle collider fixes "my square ball gets stuck on corners" instantly.
- Constraint fit: **Good** for primitives/convex; concave and heightmaps add CPU cost — fine for terrain but flag as advanced.

## 5. Joints & constraints (hinge, spring, slider, pin)
**One-liner:** Connect bodies physically: `HingeJoint` (door), `SpringJoint3D` (bouncy), `SliderJoint3D` (piston/elevator), `PinJoint3D` (chain link), `Generic6DOFJoint3D`; GameMaker has revolute/prismatic/rope/gear joints with motors; UE has Physics Constraints.
- Effort: **M–L** (a "joint" brick: pick two bricks + joint type + anchor + limits/motor; compile to joint nodes)
- Beginner impact: **High** — swings, seesaws, chains, trapdoors, pistons are the classic "physics toys" beginners want.
- Constraint fit: **Good.** Godot Jolt now ships in 4.7; note Jolt drops some legacy joint soft-limit properties — compiler must emit standard Godot joints. Deterministic within a tick.

## 6. Ragdolls
**One-liner:** Godot auto-generates `PhysicalBone3D` + pin joints from a Skeleton3D ("Create Physical Skeleton") so characters flop on death/impact.
- Effort: **L** (needs a skeleton rig; conflicts with primitives-only assets unless characters are simple articulated rigs)
- Beginner impact: **Medium-high** (death animations are a top beginner wish) but expects skinned characters EasyForge doesn't have.
- Constraint fit: **Poor–medium.** Official Godot feature, but assets are primitives — a "robot made of primitive limbs" rig could work; 3D-only. Deprioritize.

## 7. Soft-body & cloth
**One-liner:** Godot `SoftBody3D` simulates cloth/rubber from a subdivided mesh with pinned attachments (cloak demo); UE Chaos Cloth; Unreal soft-body plugin.
- Effort: **L** (UI for precision/pinning; heavy)
- Beginner impact: **Medium** — pretty but rarely gameplay-critical; known bugs in Godot soft bodies ("not for gameplay-affecting things" per docs).
- Constraint fit: **Medium.** Official, 3D-only, CPU-heavy on 3050; docs warn against gameplay use. Nice-to-have polish.

## 8. Triggers vs solid
**One-liner:** `Area2D`/`Area3D` = detection-only zones (coins, checkpoints, damage) vs bodies that block movement — the simplest true/false toggle in every engine (UE "OverlapAll" vs "BlockAll").
- Effort: **S** (an "is trigger" checkbox on any collision brick: overlaps, never blocks)
- Beginner impact: **Very high** — pickups, win zones, and dialogue triggers are usually a beginner's second feature after jumping.
- Constraint fit: **Excellent.** Deterministic, cheap, pure signal — `body_entered`/`area_entered` compile cleanly.

## 9. Continuous collision detection (CCD)
**One-liner:** Prevents fast objects tunneling through walls: Godot `RigidBody2D.continuous_cd` (ray / shape cast modes), Unity Discrete/Continuous Speculative/Continuous/Continuous Dynamic, UE MACD.
- Effort: **S** (expose an enum dropdown on the projectile/fast-body brick)
- Beginner impact: **High** — "my bullet went through the enemy" is a legendary beginner bug report; one checkbox kills it.
- Constraint fit: **Excellent.** Per-body setting, deterministic, costs CPU only when enabled — perfect fit for a compiled tool.

## 10. Sub-stepping & fixed timestep
**One-liner:** Godot runs a fixed 60 Hz physics tick (`physics_ticks_per_second`, `max_physics_steps_per_frame`); Unity/UE expose solver iterations and sub-stepping for stability under load.
- Effort: **S–M** (project-level setting, maybe exposed as "simulation quality" slider; keep 60 Hz default for determinism)
- Beginner impact: **Medium** — invisible until it isn't: fixes "game runs at different speed on different PCs" reports.
- Constraint fit: **Excellent.** Fixed timestep is exactly what a deterministic compiler wants; never expose variable-delta physics.

## 11. Gravity zones & directional/point gravity
**One-liner:** `Area2D/Area3D` override gravity inside a volume — direction, strength, zero-g, or point gravity (planet/magnet); the tutorial trick for floating/swimming.
- Effort: **S–M** (a "gravity zone" brick: shape + direction/strength or point source + combine/replace mode)
- Beginner impact: **High** — space levels, water, and "planet" games are built entirely from this one brick.
- Constraint fit: **Excellent.** Native Godot feature, deterministic, no code, works in 2D and 3D.

## 12. Buoyancy
**One-liner:** No engine ships one-click buoyancy (even UE requires force math), but every engine approximates it via upward force vs submersion depth or gravity-zone tricks (community Godot: submerged-fraction force + drag, or negative-gravity zones).
- Effort: **M** (a "water" brick that compiles submersion detection + upward force + drag; or a gravity-zone preset)
- Beginner impact: **High** for water/swimming games — and being *easier than raw engines* is a genuine differentiator here.
- Constraint fit: **Good.** Compiler-owned math keeps it deterministic; needs a water-level primitive (a plane) which fits primitives-only.

## 13. Vehicle physics
**One-liner:** Godot `VehicleBody3D` + `VehicleWheel3D` (raycast car: engine force, brake, steering) — though docs warn "known issues, not designed for realistic vehicle physics."
- Effort: **L** (3D-only, wheel/suspension UI, and the class is documented as unreliable)
- Beginner impact: **Medium-high** (kids love car games) but 2D side-view "cars" can be faked with existing platformer mechanics.
- Constraint fit: **Poor–medium.** 3D-only, flaky per official docs, heavy tuning. Faking it in 2D with velocity/friction bricks is the better EasyForge play.

## 14. Destructible geometry
**One-liner:** UE Chaos Geometry Collections fracture meshes into simulated chunks; Godot has no built-in equivalent — community does tile-swap or CSG/convex-fracture addons.
- Effort: **L** (no engine-native path in Godot; would need a compiler-emitted fragment system)
- Beginner impact: **Medium-high** (satisfying!) but hard to make feel good with primitives.
- Constraint fit: **Medium.** Deterministic preset-fragments (brick breaks into N pre-placed primitive chunks with impulses) is feasible and cheap; true Voronoi fracture is not.

## 15. Physics debugging visualization
**One-liner:** Godot's built-in **Debug → Visible Collision Shapes** (toggle shapes, contact points, colors; addons extend it) — Unity Physics Debugger shows the same in the editor.
- Effort: **S** (expose the engine's existing debug draw toggle + maybe an in-editor overlay)
- Beginner impact: **High** — "why won't my player jump?" is answered instantly when you can see colliders; classic teacher/troubleshooter tool.
- Constraint fit: **Excellent.** It's a debug draw built into Godot; the tool just surfaces it.

## 16. Inverse kinematics
**One-liner:** Godot ships `SkeletonIK3D` (FABRIK), 2D `TwoBoneIK`/`SkeletonModification2DFABRIK`, so feet land on slopes and hands grab objects.
- Effort: **L** (requires rigs/skeletons — conflicts with primitives-only assets)
- Beginner impact: **Medium** — mostly polish; needs skeletal characters.
- Constraint fit: **Poor.** Official but asset-model mismatch (note: `SkeletonIK3D` is marked deprecated in 4.7 in favor of the modifier system — avoid betting on it).

## 17. Physics-based animation
**One-liner:** Beyond ragdolls: Godot physical bones blend with animation, UE "physical animation" drives toward animation poses with physics constraints; simpler variant = bodies whose motion *is* the animation (ball = animation).
- Effort: **M–L** (full version needs rigs; the "physics is the animation" variant is S)
- Beginner impact: **Medium** for full physical animation; **high** for the trivial variant (a bouncing ball character = RigidBody, zero animation work).
- Constraint fit: **Medium.** RigidBody-as-character fits primitives perfectly; skeletal physical animation does not.

---

## Cross-cutting observations
- **The cheap cluster:** triggers, layers/masks, CCD, gravity zones, debug shapes, fixed timestep are all S-effort, native, deterministic Godot features — they're "expose what Godot already does" features, exactly a compiler's sweet spot.
- **The wow cluster:** rigidbodies and joints are M-effort and are what make a physics toy feel real.
- **The asset-model mismatch cluster:** ragdolls, soft-body, IK, true vehicles assume rigs/meshes EasyForge doesn't have — either skip or build primitives-compatible variants (articulated primitive robot, fluid "cloth" as a bobbing plane).
- **Differentiator opportunity:** buoyancy and destructibles are weak in *all* beginner tools including GameMaker; a deterministic, compiler-own buoyancy brick would be genuinely novel for a no-code tool.

---

## TOP 5 (ranked by beginner impact × constraint fit ÷ effort)

1. **Triggers vs solid (Area2D/Area3D zones)** — S effort, highest impact-per-line feature in any engine; pickups/win zones/damage are a beginner's #2 ask after jumping; pure signal, perfectly deterministic. *(Effort S, impact very high, fit excellent)*
2. **Collision layers & masks** — M effort, unlocks every gameplay rule (bullets vs enemies vs pickups) declaratively; compiles to deterministic bitmasks; the single feature that stops beginners needing "logic" bricks. *(Effort M, impact high, fit excellent)*
3. **Rigidbody dynamics (mass/forces/damping) as a body mode** — M effort, the biggest "wow" unlock (falling crates, dice, balls); native Godot, deterministic at fixed 60 Hz; pairs with #2 for gameplay rules. *(Effort M, impact very high, fit good)*
4. **Joints — hinge, spring, slider, pin** — M–L effort, but the gateway to an entire genre of "physics playground" games (swings, seesaws, chains, pistons); native Godot nodes; build the simple four joint types first, skip 6DOF. *(Effort M–L, impact high, fit good)*
5. **Gravity zones (directional + point gravity, zero-g)** — S–M effort, one brick yields space levels, water float presets, and planet games; doubles as the foundation for the buoyancy brick; native, cheap, deterministic in 2D and 3D. *(Effort S–M, impact high, fit excellent)*

**Honorable mention:** CCD toggle (S effort) — a one-dropdown fix for the most infamous beginner bug ("bullets pass through walls"); bundle it as an automatic flag on any "fast projectile" brick rather than exposing the enum.
