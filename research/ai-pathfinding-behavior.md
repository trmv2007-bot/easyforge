# EasyForge AI / Pathfinding / Behavior Features — World-Class Engine Benchmark

Scope: what Unity, Unreal, Godot, and Houdini give beginners that EasyForge currently lacks
beyond the Enemy Patrol, Follow, Rule (if/then), and Variable bricks. Godot 4.7 official, no fork,
deterministic bricks-to-GDScript compiler, no raw code, local standalone, primitive + procedural
assets only.

Legend — Effort: S (days), M (1–3 weeks), L (1+ month). Beginner impact: how much a first-time
no-code maker notices/wins from it. Constraint fit: how well it survives deterministic compile +
no-code + local-only constraints.

---

## 1. Navigation meshes (2D + 3D)
One-liner: bake a walkable surface from tilemaps/colliders (2D) or level geometry (3D) so enemies
take real routes around walls instead of bumping into them.
Reality check: Unity ships NavMeshSurface + NavMeshPlus2D (tilemap/sprites/colliders → mesh, bake
button, agent types); Unreal ships Recast navmesh with NavModifiers and Nav Links (jump/ladder
links); Godot 4 has NavigationRegion2D/3D with polygon baking built in. A* over the navmesh graph
with funnel smoothing is the standard engine implementation.
Effort: M (bake-from-selection "Navigation Brick", region resources, deterministic).
Beginner impact: Very high — it is the single biggest visible "why does my enemy get stuck" fix.
Constraint fit: Strong — Godot 4.7 has NavigationServer2D/3D; the compiler can emit the bake +
agent setup deterministically from brick properties.

## 2. Pathfinding agents with dynamic obstacle avoidance
One-liner: a NavigationAgent-style node that follows the path while pushing around other agents
and moving obstacles (RVO avoidance), with speed, acceleration, stopping distance, arrival radius.
Reality check: Unity NavMeshAgent exposes exactly these knobs (speed, angular speed, acceleration,
stopping distance, autoBraking off = smooth patrol, quality, priority); Unreal uses Detour crowds;
Godot 4.4+ NavigationAgent2D/3D with avoidance_enabled and velocity_computed, NavigationObstacle2D/3D
with radius for dynamic "move-away-from-me" objects, avoidance_layers/masks.
Effort: M.
Beginner impact: High — turns "chase" from a straight line into "hunt around the table".
Constraint fit: Strong — pure brick properties (speed/accel/radius/layer masks), fully deterministic.

## 3. Steering behaviors (seek, flee, arrive, wander, pursue/evade, path following)
One-liner: movement is a desired velocity computed from simple force rules, so enemies glide,
slow down before stopping (arrive), loiter believably (wander), and lead a moving target
(pursue/evade).
Reality check: Craig Reynolds 1987 classics, taught in every engine tutorial; Unity and Godot both
expect you to write them, Unreal relies on navmesh steering. Weighted sum of forces + clamp to max
speed is the standard beginner formula.
Effort: S–M (each behavior is ~20 lines of deterministic GDScript; wander needs a seeded RNG).
Beginner impact: High — arrive/wander alone makes patrols look "designed" instead of robotic.
Constraint fit: Strong — deterministic if RNG is seeded from the level; no engine hooks needed.

## 4. Flocking / crowd behaviors (separation, alignment, cohesion)
One-liner: give each boid three neighborhood rules — don't crowd, match heading, move together —
and groups (bird flocks, fish schools, market crowds) emerge with no scripting per group.
Reality check: Unity's beginner "Crowd Simulation" course and the classic boids demo; Unreal uses
Mass/MassCrowd; Godot does it with the same avoidance layer. Weight recipes per crowd type
(tight flock vs loose marketplace) are the documented pattern. Piggybacks on #2's avoidance.
Effort: S (on top of steering) to M (mass scaling).
Beginner impact: Medium — "wow" factor for swarms and townspeople.
Constraint fit: Good — local sim, no netcode; performance needs an agent-count cap for safety.

## 5. Behavior trees
One-liner: a visual tree of selector/sequence nodes with condition decorators and reusable action
leaves, so "if I can see player → chase → attack, else patrol" is assembled by dragging, not
coding.
Reality check: Unreal's Behavior Tree editor + observer aborts is the gold standard; Unity has the
Unity Behavior package; Godot relies on community LimboAI (BT editor + blackboard + visual
debugger, GDExtension, Godot 4.6/4.7 support). EasyForge's Rule brick is a flat if/then — a BT is
Rule bricks nested into ordered trees with abort/rerun semantics.
Effort: M (visual editor + BTPlayer-equivalent runtime, deterministic ordering).
Beginner impact: Very high — the #1 feature beginners ask for after patrol.
Constraint fit: Good — emits deterministic ordered tree evaluation; LimboAI is MIT if in-engine
reference is needed, but EasyForge should compile trees to its own deterministic evaluator.

## 6. State machines (FSM + hierarchical FSM)
One-liner: states (Idle/Patrol/Alert/Chase/Attack/Flee) with event-driven transitions; nesting
states so "lost the player" exits every combat sub-state at once.
Reality check: Unreal StateTree, LimboAI LimboHSM (nestable, event-based); the standard FSM has
exactly one active state and condition/event transitions. EasyForge already has a Variable brick
that can hold a state string — this is that pattern made visual and first-class.
Effort: M (S) for flat FSM, (M) for hierarchy + event transitions.
Beginner impact: Very high — maps directly onto the enemy pattern list users already imagine.
Constraint fit: Strong — a state variable + transition rules compile to a deterministic switch.

## 7. GOAP
One-liner: define goals and actions with preconditions/effects, and the planner searches for a
cheap action sequence, so enemies emerge surprising plans (take cover → flank → push) without
hand-wired transitions.
Reality check: F.E.A.R. (2005, Jeff Orkin) origin; A* over world states. Educational but rarely a
beginner need; usually deferred. Unity has asset-store GOAP; Unreal users hand-roll EQS+BT hybrids.
Effort: L (planner, action libraries, debugging).
Beginner impact: Low–medium at launch (niche; most users want readable enemies, not emergent ones).
Constraint fit: Weak-ish — search cost and nondeterminism risk; keep out of v1.

## 8. Utility AI
One-liner: score every candidate action (health, distance, ammo, threat through response curves)
and pick the best, giving smooth priorities instead of hard on/off transitions.
Reality check: The Sims needs system; documented response-curve pattern (each consideration maps an
input through a curve to 0–1, multiply scores). Composes with FSM/BT as a selector node.
Effort: M (curve editors + scoring node in the tree).
Beginner impact: Medium — invisible craft, but removes "why won't it just retreat" complaints.
Constraint fit: Good — deterministic scoring; curves are data, not code.

## 9. Blackboard / AI memory
One-liner: a shared key-value store (target, last seen position, alert level, home post) that both
decision logic and movement read, so "search where I last saw you" is one lookup.
Reality check: Unreal Blackboard + Max Age ("forget stale actors" after 5s, Lose Sight Radius >
Sight Radius to stop flicker); LimboAI has a blackboard with scopes/parameters. The Variable brick
is EasyForge's precursor — a scoped, inspectable key-value table per agent is the upgrade.
Effort: S–M.
Beginner impact: High — "enemy remembers where you were" is a memorable beginner win.
Constraint fit: Strong — plain dict on the compiled node, fully deterministic and debuggable.

## 10. Perception: sight cones, hearing, team/damage senses
One-liner: configurable senses (sight radius, lose-sight radius, peripheral/vision half-angle, line
of sight checks, hearing radius, "felt damage") that feed the blackboard — see player → chase,
lose them → search.
Reality check: Unreal AI Perception component (AISense_Sight/Hearing/Damage/Touch; Lose Sight Radius
hysteresis; Max Age forgetting) is the reference; a sight cone brick = radius + half-angle + LOS
raycast.
Effort: M (sight cone S, full sense set M).
Beginner impact: Very high — the "why did it notice me?" loop is core to enemy feel.
Constraint fit: Strong — raycasts + angles are deterministic, local-only.

## 11. Agent avoidance + neighbor filters
One-liner: agents on the same avoidance map push each other aside instead of overlapping, with
masks (player chases, civilians dodge) and prediction horizons.
Reality check: Godot 4 NavigationAgent avoidance (velocity_computed/safe_velocity, time_horizon_*
, avoidance_layers/masks, dynamic NavigationObstacle radius); Unity obstacleAvoidanceType quality +
priority; noted engine caveat: avoidance has no physics info, so extreme cases need the physics
body. For EasyForge: expose avoidance as an on/off + layer-mask property on the Path brick.
Effort: S (wrapper) if navigation exists, else M.
Beginner impact: High — fixes enemies stacking into one pixel-wide column.
Constraint fit: Strong.

## 12. Crowd simulation at scale
One-liner: hundreds of agents streaming through a scene on roads/goal-directed flow with LOD,
without one script each.
Reality check: Unreal Mass/MassCrowd (ECS), Unity DOTS/ECS; for a no-code beginner tool the
realistic version is "many agents sharing one behavior resource + a cap" rather than true ECS.
Effort: L (true scale) / M (doable beginner version: shared BT + agent pool).
Beginner impact: Medium.
Constraint fit: Medium — no netcode needed, but Godot-node-per-agent caps and determinism concerns;
ship as an opt-in with an agent budget.

## 13. Enemy AI pattern library (patrol, chase, attack, flee, guard, return home)
One-liner: named, parameterized behavior presets — waypoint patrol with wait times, chase within
leash range, attack with cooldown + range, flee when low HP, guard a post and return to it.
Reality check: every engine tutorial builds these first; EasyForge has patrol + follow already —
this is the completion of the standard set with per-pattern knobs (wait time, leash, cooldown,
aggro radius, home return).
Effort: S per pattern, M as a coherent library.
Beginner impact: Very high — directly matches what users ask for ("how do I make it run away?").
Constraint fit: Strong.

## 14. Boss AI with phases
One-liner: health-threshold phases, each with its own attack pool, telegraph → windup → attack →
recovery cycles, brief invulnerable transitions, and enrage timers.
Reality check: the documented standard architecture: server-side state machine, phase pool attacks
respecting cooldowns, 4-beat telegraph cycle, 75/50/25% thresholds, phase-entry invulnerability to
prevent skipping. EasyForge needs: Phase brick (threshold + child behavior), Attack brick with
windup/cooldown windows.
Effort: M.
Beginner impact: Very high — bosses are the aspirational first "big" enemy.
Constraint fit: Strong — thresholds + timers are data, deterministic, no raw code.

## 15. Difficulty scaling (static tiers + adaptive DDA)
One-liner: difficulty tiers that multiply enemy HP/damage/speed, plus an optional adaptive mode
that reads recent performance (deaths, damage taken ratio, time-to-kill) over a rolling window and
clamps enemy knobs within designer-signed bounds.
Reality check: DDA literature: rolling 5-min window, struggle score 0–1, bounded multipliers
(enemy health 0.8–1.6x, damage 0.7–1.5x), never rewrite authored content outside clamps; simpler
level-delta stat tables and AI-director pacing as static alternatives.
Effort: S (tier multipliers) / M (adaptive with rolling window).
Beginner impact: High — "Easy/Normal/Hard" is expected; adaptive keeps the game in flow.
Constraint fit: Strong — a difficulty number is exactly a Variable the bricks already support.

## 16. Procedural content generation (levels + enemy placement)
One-liner: generate room layouts (room-connect algorithms / tilemap-based generators) and place
enemies/items with constraints (min distance from spawn, boss room, treasure room) from a seed.
Reality check: documented generators: closed-room expansion + open connecting sides (dungeon),
PCG-BT (behavior trees as generators — modular segments composed into trees), tile-array +
neighbor-rule methods; evaluation metrics (room count, path length, enemy spacing) exist as
benchmarks. For EasyForge the beginner shape is: seeded room templates + rule-based connections +
enemy slots.
Effort: M (placement + seeded templates) / L (full generator authoring).
Beginner impact: High for "endless/replayable" projects; medium otherwise.
Constraint fit: Good — seeded RNG keeps compile deterministic; validate "reachable" with navmesh
path checks.

## 17. AI debugging / visualization
One-liner: in-game overlay showing each enemy's current state, target, path line, vision cone,
and decision — so beginners can see why the AI did something instead of guessing.
Reality check: Unreal AI Debugging (apostrophe key, numpad 0–4 cycling navmesh/behavior tree/EQS/
perception); Unity Gizmos pattern (draw path corners, detection spheres, vision); industry advice:
add debug draws (path lines, FOV cones, current BT node, steering vector) BEFORE tuning. For a
no-code tool this is not optional — it is the feedback channel.
Effort: S–M (draw calls + a debug toggle brick).
Beginner impact: Very high — transforms opaque failures into fixable ones.
Constraint fit: Strong — deterministic draw data, editor + runtime toggle.

## 18. Tactical AI (cover usage, suppression, flanking, squad coordination)
One-liner: enemies pick scored cover (protection, fire angle, exit paths), suppress while allies
move, and flank when the target is pinned.
Reality check: cover systems need tagged cover points, per-tick scoring, squad spacing rules
(avoid stacking, one suppressor + one mover), and metrics (time exposed, flank success). This is
advanced: reference implementations are GDC talks (Believable Tactics for Squad AI) and
hand-built systems, not out-of-box engine features for beginners.
Effort: L.
Beginner impact: Low at launch (aspirational; most beginners won't configure cover scoring).
Constraint fit: Weak — heavy authoring; consider a simplified "Guard Brick: take cover when hit"
later.

## 19. Houdini-style procedural asset generation
One-liner: node-graph procedural generation of meshes/textures/layouts (Smart Assets, Digital
Assets) reused for levels and props.
Reality check: Houdini's procedural SOP networks and Solaris/TOPs pipelines produce thousands of
asset variants; as a *teaching* reference it validates "parameterize once, generate many" —
directly analogous to EasyForge bricks compiling to variants. Godot-side equivalent for this
product is procedural mesh generation in GDScript (ArrayMesh/PrimitiveMesh + noise/seeded params),
not importing Houdini.
Effort: L.
Beginner impact: Medium (art-style breadth) — but adjacent to the core AI gap.
Constraint fit: Medium — assets must stay procedural/primitives; this is more art-pipeline than AI.
Keep separate from AI scope.

---

## Additional engine references worth noting
- Unity: NavMeshSurface bake + agent type, NavMesh Links (jump traversal), Navigation Modifier
  Volumes (area costs, e.g. slow zones), NavMeshPlus2D for tilemaps.
- Unreal: Behavior Tree observer aborts (instant re-evaluation), EQS (environment queries —
  "find a spot 500–1000 units from player that has LOS" as a node), StateTree, Mass crowds.
- Godot 4.7: NavigationRegion2D/3D, NavigationAgent2D/3D avoidance, NavigationObstacle2D/3D
  (static polygon or dynamic radius), LimboAI (MIT) for BT/HSM + blackboard + visual debugger.
- Houdini: procedural generation as node graphs; crowd/TOPs pipelines — concept transfer only.

---

## TOP 5 — RANKED (recommendation order for EasyForge)

1. **Navigation Mesh + Pathfinding brick (2D & 3D, with dynamic obstacles)** — the foundation
   every other feature stands on; fixes the #1 beginner complaint ("enemy gets stuck"); pure
   data-driven brick properties; Godot 4.7 NavigationServer2D/3D does the work; deterministic
   compile is trivial. Effort M, beginner impact very high, constraint fit strong.

2. **Perception brick (sight cone + hearing + LOS + memory)** — the sense layer that makes patrol
   → alert → chase → search readable; teaches cause-and-effect ("it saw me"); radius/angle/raycast
   are deterministic; blackboard memory (last-seen position, forget timer) rides along.
   Effort S–M, beginner impact very high, constraint fit strong.

3. **State Machine brick (FSM + hierarchy) with blackboard/AI memory** — completes the enemy
   pattern library (guard, flee, return home, boss phases as child states); the existing Variable
   brick becomes a proper inspectable blackboard; compiles to a deterministic switch/transition
   table. Effort M, beginner impact very high, constraint fit strong.

4. **Behavior Tree brick (visual editor + deterministic evaluator)** — the step up from Rule
   bricks: nested selector/sequence trees with decorators, reusability, and the answer to "my AI
   is too complicated for if/then"; reference implementations exist (LimboAI MIT, Unreal BT).
   Effort M, beginner impact very high, constraint fit good (must ship its own deterministic
   evaluator, not a plugin dependency).

5. **AI Debugging Visualization + steering arrive/wander** — the feedback layer (state labels,
   path lines, vision cones, live decision readout) plus the two steering behaviors that make
   movement feel alive (slow down on arrival, believable idling). Cheap, high perceived quality,
   and the debug layer de-risks every feature above it. Effort S, beginner impact high,
   constraint fit strong.

Runner-ups: enemy pattern library completion (S, fold into #3), difficulty scaling (S–M, Variable
+ multipliers), flocking/crowd (S on steering, cap agents), boss phases (M, child of #3), PCG
enemy placement (M, seeded). Defer: GOAP (L, niche), full tactical cover AI (L), true ECS crowd
scale (L), Houdini-style asset pipelines (out of AI scope).
