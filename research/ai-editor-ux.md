# AI + Editor Experience — Gap Analysis

Compared against Rosebud AI (Phaser + "Rosie" chat agent), GDevelop 5 AI (Ask/Build
agent modes with plan-and-status UI), Ludus AI (in-editor agent with staged approvals),
Decart, Remix (voice prompt-to-game), Summer Engine (Godot 4 design-by-conversation),
plus Cursor-style diff-review patterns (Cline "Explain Changes", Glassbox).

**Architecture note:** the brick graph JSON is the single IR; the AI emits IR mutations
(a JSON patch/diff over bricks); the compiler stays deterministic.

## Feature inventory

1. **Iterative prompt refinement** — a persistent chat panel where every message mutates
   the current game; AI never regenerates from scratch, it outputs a structured diff
   (add/modify/remove/reconnect bricks + param changes). M effort, HIGH impact, perfect
   fit (deterministic compiler + small vocabulary makes chat-to-IR far more reliable
   than chat-to-code — Rosebud's known weakness).
2. **Follow-up NL edits** ("add a double jump", "add a boss") — constrained to known
   brick types + param deltas, so unknown concepts get composed, not hallucinated. M,
   HIGH, excellent fit — the closed brick vocabulary is our competitive advantage.
3. **AI explains what it changed** — plain-language summary rendered from the IR diff,
   no second LLM call needed. S effort, HIGH impact, builds trust and teaches.
4. **Undo/redo of AI actions** — every AI turn is one undo step; the IR diff is the
   transaction; undo = apply inverse diff. S effort, HIGH impact, the safety net.
5. **Visual diff of AI changes** — side-by-side/highlighted view (green added, red
   removed, yellow param chips) shown before applying. S-M, medium-high, excellent fit.
6. **AI suggests the next bricks** — "has Jump + Move but no enemy -> suggest
   EnemyPatrol + Score" from a curated pattern library (no LLM cost). S (rule-based),
   HIGH for beginners, kills blank-canvas paralysis.
7. **Brick-scoped NL editing** — select a brick, type "make this enemy slower", only
   that brick's params change. Cursor-Ctrl-K scoped to one node. S-M, HIGH.
8. **AI asset generation** — constraint-conflicted with "primitives + procedural color";
   the cheap on-stance variant is AI-tuned procedural parameters (palette themes, shape
   params, sound envelopes). M for procedural-parameter AI.
9. **Playtest-by-AI (auto balance)** — headless Godot + scripted input agent + telemetry;
   "level 3 has 78% death rate" -> suggest param tweaks. L effort (M for an MVP scripted
   run). HIGH if done.
10. **AI-generated per-game tutorial** — auto-generate a "controls/how to play" overlay
    from the IR (bricks with Controls mappings + WinLose goals). S, medium-high.
11. **Voice input** — local STT (Whisper small/medium on RTX 3050) -> same text path. S,
    medium; must fit the offline/BYOK stance.
12. **Multi-turn memory** — per-project preference store injected into the planner
    prompt. S-M, medium.
13. **Error self-correction** — validate the IR BEFORE compiling; feed compiler errors +
    the diff back for a bounded retry (max 2-3), then auto-revert to last good snapshot.
    M effort, HIGH impact — the antidote to Rosebud's #1 criticism.
14. **Remix my game (cross-project recall)** — merge two project JSONs, AI proposes a
    merged graph with conflict resolution. M, medium-high, local-only = privacy-safe.
15. **Template galleries by genre** — just brick JSON files; AI can personalize from a
    prompt. S, medium-high, perfect fit.
16. **Collaborative editing** — out of scope (no netcode; L distributed-systems problem).
    Async "share project file" is the S-effort offline substitute.

## Deep dive: turning "add a double jump" into a brick-graph mutation

Copy GDevelop/Ludus discipline with a much smaller action space:
1. Read state: serialize the current brick graph (small enough to fit in context).
2. Plan: one LLM call proposes a structured edit (add/modify/remove ops + param deltas)
   plus a human-readable summary.
3. Validate BEFORE compiling: a static checker enforces the brick grammar (required
   ports, param ranges, one Player, no duplicate ids, WinLose present).
4. Apply as one transaction: push ONE undo entry, record the diff for the visual view.
5. Compile + verify: deterministic bricks->GDScript. If the compiler errors, feed the
   error back for a bounded self-correction loop, then fall back to "reverted to last
   working version."
6. Explain: render the summary from the diff (no extra LLM call).

**Key insight:** iteration quality is decided by the IR, not the model. The brick graph
makes every AI edit reviewable, reversible, and validatable — that IS the differentiator.

## Top 5 (ranked)

1. **Iterative chat that mutates the brick graph** (#1/#2) — the conversation is the
   editor; highest beginner impact; the IR makes it far more robust than Rosebud's code
   editing.
2. **IR validation + bounded self-correction loop** (#13) — the trust guarantee that
   makes chat editing safe; unique advantage of a deterministic compiler; directly
   attacks the category's biggest complaint.
3. **AI explains what it changed + one-click undo of AI turns** (#3/#4/#5) — cheap (S) on
   top of the diff, massive trust/teaching value, and the safety net for experiments.
4. **AI suggests the next bricks** (#6) — kills blank-canvas paralysis for beginners;
   mostly a curated pattern library, low cost, high delight.
5. **Brick-scoped natural-language editing** (#7) + voice input (#11) — "make this enemy
   slower" on a selected brick matches the inspector UX users already know; voice is a
   cheap accessibility win with local STT.
