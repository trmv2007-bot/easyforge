# Gameplay Logic & Systems — Gap Analysis

**The structural gap (read first):** Every competitor shares one architectural primitive
EasyForge lacks — **conditional logic attached to objects**. Construct = event sheets
(if-then). GDevelop = events + behaviors + State Machine extension. GameMaker =
per-object events. RPG Maker = event commands gated by Switches/Variables. Dreams =
input/output/processing/sensor gadgets wired together. GB Studio = 150+ event types.

EasyForge's model is a **fixed palette of pre-canned brick types**. Each new mechanic
currently needs a hand-written brick + compiler codegen path. So EasyForge scales as
**O(new brick types)**, competitors as **O(new rules on existing bricks)**.

**Therefore the single highest-leverage change is a Rule / If-Then brick** that reifies
conditions into first-class data nodes. That one primitive unlocks most of the checklist
without touching the compiler per feature.

## Impact-per-effort table

| # | Feature | Effort | Impact | Fit | Priority |
|---|---|---|---|---|---|
| 1.7 | Game-feel knobs (coyote/buffer/var-jump/asym-gravity) | S | Very high | Perfect | v1.5 #1 |
| 1.6 | Physics tweaks (one-way, bounce, friction) | S | High | Excellent | v1.5 #2 |
| 1.2 | Variables & scopes | M->L | Very high | Excellent | v1.5 #3 |
| 1.1 | Rule / if-then brick | L | Very high | Good | v1.5 #4 (enabler) |
| 1.4 | Timers, cooldowns, wait, time scale | S-M | High | Excellent | v1.5 #5 |
| 1.9 | Inventory / items | M | High | Good | v2 |
| 1.3 | State machine | S-M | High | Good | v2 |
| 1.5 | Random & spawn waves | S* | High | Good | v2 (*needs 1.1+1.4) |
| 1.13 | Win/lose variety | S-M | Medium-high | Excellent | v2 |
| 1.14 | Lives/health UI | S-M | High | Good | v2 |
| 1.8 | Screen shake / hit-stop | S-M | High | Good | v1.5 cheap win |
| 1.10 | Dialogue (linear->branching) | M->L | Medium-high | Good | v2 |
| 1.11 | Pathfinding chase | M | Medium-high | Good | v2 |
| 1.15 | Reusable logic / custom bricks | M-L | Indirect high | Good | v2 (force multiplier) |
| 1.12 | Day-night / world state | M | Medium | Moderate | v2+ |
| 1.16 | 2.5D | L | Low-medium | Moderate | v2+ |

## Top 5 (ranked)

1. **Ship the four game-feel knobs as Controls-brick params.** Coyote time ~0.1s, jump
   buffer ~0.12s, variable jump height (jump-cut x0.45), asymmetric gravity (fall 1.7x
   rise). One afternoon of compiler work; invisible-when-right, game-ruining-when-absent.
   Biggest perceived-quality jump per hour spent.
2. **Physics surface params on Platform/Ground brick** — one-way collision toggle,
   bounce 0-1, friction 0-1 sliders plus ice/trampoline presets. All one-line Godot
   writes (PhysicsMaterial, one_way_collision). Kills the #1 beginner level-design
   frustration.
3. **Variables with scopes as a first-class brick** — global/scene/per-object number +
   boolean + text, with a Variable brick (Get/Set/Add/Compare) and params on existing
   bricks. Backed by a generated GameState autoload + per-node metadata dict.
   Highest-frequency beginner request; foundation for inventory, win/lose variety, state.
4. **One Rule brick: condition slots -> action slots.** Curated condition vocabulary
   (Collided-with / Variable-compare / Timer-elapsed / Key-pressed / State-equals) and
   action vocabulary (Add-variable / Set-state / Start-timer / Spawn / Play-sound). The
   structural fix that converts the roadmap from O(new brick types) to O(new rules),
   unlocking state machines, waves, inventory, and win/lose variety at near-zero
   marginal compiler cost.
5. **Timers as bricks, not scaffolding.** Per-node named timers (start/reset/is-elapsed),
   an "every N seconds" repeat mode, a Wait action, and a global time-scale toggle
   (slow-mo/hit-stop). Composes with variables and rules to unlock cooldowns, power-up
   durations, waves, and survival timers.

**Sequencing note:** #3 and #4 share the same compiler plumbing (generated state +
condition eval), and #5 is trivial once #3 exists. Recommended v1.5 bundle:
#1 + #2 (week 1), then #3 -> #5 -> #4 as one continuous plumbing build.
