# EasyForge: AI + Editor Experience Gap Analysis (vs. Rosebud AI, Ludus, GDevelop, prompt-to-game tools)

Method: feature-by-feature comparison grounded in web research of Rosebud AI (Phaser + "Rosie" chat agent), GDevelop 5 AI (Ask/Build agent modes with plan-and-status UI), Ludus AI (in-editor agent with staged approvals), Decart (real-time world models), Remix (voice prompt-to-game), Summer Engine (Godot 4 design-by-conversation), plus Cursor-style diff-review patterns (Cline "Explain Changes", Glassbox). Each feature is mapped onto EasyForge's architecture: brick graph JSON is the single IR, the AI emits IR mutations (a JSON patch/diff over bricks), and the compiler stays deterministic.

---

## 1. Iterative prompt refinement (chat that edits the existing game, not just a first draft)
1) A persistent chat panel where every message mutates the current game; "make it harder" re-plans against the existing graph.
2) AI never regenerates from scratch — it outputs a structured diff over brick JSON (add/modify/remove/reconnect bricks + parameter changes). The compiler then re-emits GDScript. This is exactly GDevelop's Build agent and Summer Engine's "describe, play, re-describe" loop.
3) Effort: M (needs a diff-schema, a planner prompt, and chat UI wired to the IR).
4) Impact: HIGH — the first draft is never what the user wants; the conversation IS the product for beginners.
5) Fit: Perfect. Deterministic compiler + small brick vocabulary makes chat-to-IR mutation far more reliable than chat-to-code (Rosebud's known weakness: "chat-based fixes often break other mechanics" — nilo.io review).

## 2. Follow-up natural-language edits ("add a double jump", "add a boss")
1) Targeted requests that add/modify bricks and their parameters in context.
2) "Add a double jump" = attach Jump brick with jump_count=2 to Player + retune existing Jump params; "add a boss" = instantiate an EnemyPatrol brick variant + Health brick + WinLose trigger. The AI is constrained to emit known brick types + parameter deltas, so unknown concepts get composed, not hallucinated.
3) Effort: M.
4) Impact: HIGH — this is the #1 use case in every reviewed tool.
5) Fit: Excellent. The closed brick vocabulary is EasyForge's competitive advantage over Rosebud (open-ended JS) and GDevelop (open-ended events).

## 3. AI explains what it changed ("Explain Changes")
1) After each AI turn, a plain-language summary of the mutation: "Added an Enemy Patrol brick, raised gravity 20%, added a second checkpoint."
2) Trivially derivable from the IR diff: each diff op has a brick id + param deltas, so the explanation is templated from structured data (no second LLM call needed for the common case). Mirrors Cline's "Explain Changes" button and Glassbox's review notes.
3) Effort: S.
4) Impact: HIGH — builds trust and teaches the user what bricks do (GDevelop explicitly markets this: "watch it work while it explains the steps").
5) Fit: Excellent; the structured diff makes explanations accurate by construction.

## 4. Undo/redo of AI actions (first-class AI history)
1) Every AI turn is one undo step; user can roll back a chat edit like a manual edit.
2) The IR diff is the transaction; undo = apply inverse diff. Snapshot/restore of brick JSON is trivial (small data). No compiler involvement.
3) Effort: S (if undo already exists for manual edits, AI just reuses it).
4) Impact: HIGH — Rosebud users report breaking games via chat; undo is the safety net.
5) Fit: Perfect.

## 5. Visual diff of AI changes (brick-graph diff view)
1) Side-by-side / highlighted view showing which bricks were added, changed, or removed, with parameter before→after values.
2) A JSON-diff renderer over the brick graph (green added bricks, red removed, yellow param chips) shown before applying — like Cursor/Glassbox diff review. Deterministic since it's data, not code.
3) Effort: S-M.
4) Impact: MEDIUM-HIGH — makes reviewable edits visible to non-readers.
5) Fit: Excellent.

## 6. AI suggests the next bricks ("you added jumping — add an enemy?")
1) Context-aware suggestions of the next 1-3 bricks to wire in, one-click.
2) A rules/heuristic layer over the graph: "has Jump + Move but no enemy → suggest EnemyPatrol + Score". Could be a static pattern library (no LLM cost) or LLM-assisted. Rosebud/GDevelop do the LLM version; a curated pattern library is more reliable.
3) Effort: S (rule-based) / M (LLM).
4) Impact: HIGH for beginners — kills "what do I do next" paralysis.
5) Fit: Excellent; closed vocabulary makes suggestion space enumerable.

## 7. Natural-language editing of an individual brick (brick-scoped chat)
1) Select a brick, type "make this enemy slower", and only that brick's params change.
2) Brick id + NL instruction → parameter mutation for that brick subtree. Equivalent of Cursor's Ctrl+K scoped to one node. Constrains blast radius to one brick — the safest AI edit mode.
3) Effort: S-M.
4) Impact: HIGH — matches the inspector UX users already know.
5) Fit: Excellent.

## 8. AI asset generation (sprites/sounds/materials from text)
1) "Pixel-art style" sprite, procedural sound, palette prompt.
2) Constraint-conflicted: "assets are primitives + procedural color". A cheap local variant: LLM-assisted procedural parameters (palette themes, shape parameters, sound envelopes) — i.e., AI tunes the procedural generator rather than generating textures. Real image/audio gen (Rosebud's asset tab) needs network/GPU and breaks the offline/16GB constraint.
3) Effort: M for procedural-parameter AI; L for real asset gen.
4) Impact: MEDIUM.
5) Fit: WEAK for true asset gen; GOOD for AI-driven procedural themes.

## 9. Playtest-by-AI (auto balance)
1) The app plays the compiled game headless via scripted AI players, reports "level 3 has 78% death rate", and suggests parameter tweaks (enemy speed, jump height) — or applies them.
2) Strong fit technically: Godot headless + scripted input agent + telemetry from brick params. Ludus/GDevelop rely on human playtests; nunu.ai/ManaMind do paid overnight agent QA. Summer Engine markets plain-language balance tuning. Academic precedent: "Dungeon Master" RL agent tunes params to target difficulty (CMU 2023).
3) Effort: L (AI player + telemetry + tuning loop) — but an MVP version is M: scripted run of a fixed input sequence measuring deaths/time, then a "balance slider" suggestion.
4) Impact: HIGH if done — beginners cannot judge balance; "make it harder" becomes measurable, not vibes.
5) Fit: Good (headless Godot works offline, no netcode).

## 10. AI-generated per-game tutorial / onboarding
1) After generation, the AI writes a short in-game tutorial ("Use arrows to move, press space to jump") or a "how to play" screen tuned to the actual brick graph.
2) Derived from the IR: bricks with Controls mappings + WinLose goals → templated tutorial text (LLM optional). Even simpler: auto-generate a "controls" overlay from the remappable Controls data already in the inspector.
3) Effort: S.
4) Impact: MEDIUM-HIGH — first 30 seconds decide whether a beginner keeps playing.
5) Fit: Good.

## 11. Voice input for prompts
1) Speak the game description/edits instead of typing.
2) Local STT (Whisper small/medium runs on RTX 3050) → same text path as chat. Remix (mobile) explicitly markets voice prompting ("plain English or your voice").
3) Effort: S (local whisper.cpp/STT integration) — but must fit the offline/BYOK stance.
4) Impact: MEDIUM — lowers typing barrier, mostly for younger users.
5) Fit: Good with a bundled local STT; bad if it implies a cloud service.

## 12. Multi-turn memory across sessions
1) "Remember: I don't like zombies" / project memory the AI recalls next session.
2) A small per-project memory store (preferences, rejected suggestions, naming conventions) injected into the planner prompt. GDevelop notes "New chat" per task to avoid confusion; Ludus keeps "long-term memory of your project."
3) Effort: S-M (local JSON memory + prompt injection).
4) Impact: MEDIUM — compounds with iterative editing.
5) Fit: Good (local file).

## 13. Error self-correction when the compiler/AI breaks something
1) If a generated mutation produces invalid GDScript (or fails to compile), the app detects the error and retries automatically, showing the user "fixing…" rather than a broken game.
2) EasyForge's unique advantage: the error surface is small and structured. Compiler errors + a static graph validator (missing required connections, param ranges) feed back into the AI loop with the brick-diff as context. Pattern from AI-game-builder repo (GDD → code → validator → correction loop) and LASSI/LLM-ARC self-correction loops. Crucially: validate the IR BEFORE compiling, so most failures never reach GDScript.
3) Effort: M.
4) Impact: HIGH — Rosebud's #1 criticism is chat edits breaking games; a validator + retry loop is the antidote.
5) Fit: Excellent — deterministic compiler gives a hard check that LLM-first tools lack.

## 14. Remix my game (cross-project recall)
1) "Combine my space shooter with my dungeon crawler" / remix a template/own project.
2) Cross-project graph merge: load two project JSONs, union the brick vocabularies, AI proposes a merged graph with conflict resolution (duplicate Controls, two Players). Rosebud markets remixing public projects; cross-project recall of the USER'S OWN projects is a privacy-safe, offline version.
3) Effort: M.
4) Impact: MEDIUM-HIGH — reuse is how beginners make their second and third games.
5) Fit: Good (local projects only).

## 15. Template galleries by genre
1) Curated starting graphs: platformer, shooter, puzzle, dodger — each a complete brick graph.
2) They're just brick JSON files; the AI can also personalize a template from a prompt ("make it spooky"). Rosebud offers starter templates; this is trivially aligned with the IR.
3) Effort: S.
4) Impact: MEDIUM-HIGH — the fastest path from blank page to playable.
5) Fit: Perfect.

## 16. Collaborative editing
1) Real-time multi-user editing of the same brick graph.
2) Explicitly out of scope: "local standalone games, no netcode" — and CRDT sync of the graph + AI turn arbitration is an L-effort distributed-systems problem. Mentioned only to close it out: async "share project file" (send .json) is the S-effort offline substitute.
3) Effort: L (rejected).
4) Impact: LOW for EasyForge's single-player local positioning.
5) Fit: BAD.

---

## Deep dive: how to turn "add a double jump" into a brick-graph mutation

The reviewed tools split into two camps. Rosebud/Gameer let the LLM edit free-form code — fast first draft, fragile iteration ("you change one mechanic and another part breaks"). GDevelop and Ludus constrain the AI to structured, engine-native objects (events, Blueprint nodes) with approval steps. EasyForge should copy GDevelop/Ludus discipline, with a much smaller action space:

1. Read state: serialize the current brick graph (ids, types, params, connections) — small enough to fit in-context, always current.
2. Plan: one LLM call proposes a structured edit: `{ops: [{op: add, type: Jump, params:{jump_count:2, attach_to:"player"}}, {op: modify, id:"jump1", params:{height:-10}}]}` plus a human-readable summary. This is the "Planner/Executor" split the industry converged on, with the Planner being the only expensive call.
3. Validate BEFORE compiling: a static checker enforces the brick grammar — required ports connected, param ranges, one Player, no duplicate ids, WinLose present. A failed validation returns a structured error to the planner for one retry.
4. Apply as one transaction: apply ops to brick JSON, push ONE undo entry, record the diff for the visual-diff view.
5. Compile + verify: deterministic bricks→GDScript. If the compiler errors (rare post-validation), feed the compiler error + the diff back for a bounded self-correction loop (max 2-3 attempts), then fall back to "reverted to last working version" rather than shipping a broken build.
6. Explain: render the summary from the diff ("Player can now jump twice; jump height reduced 15%") — no extra LLM call.

Key insight from the research: iteration quality is decided by the IR, not the model. Rosebud's iteration pain comes from editing unstructured code; EasyForge's brick graph makes every AI edit reviewable, reversible, and validatable — that IS the differentiator, and features 1-5 and 13 are how it gets productized.

## Deep dive: error recovery
- Pre-compile IR validation catches ~all AI mistakes for free (closed vocabulary).
- Bounded retry loop with the compiler error as feedback (LLM-ARC/LASSI/ai-game-builder pattern); cap attempts, then auto-revert to last good snapshot with a plain-language message.
- Persistent local memory of past validation failures (ai-game-builder's "memory of past failures") reduces repeat failures.

## Top 5 ranked

1. **Iterative chat that mutates the brick graph (#1/#2)** — the conversation is the editor; highest beginner impact; EasyForge's IR makes it far more robust than Rosebud's code editing.
2. **IR validation + bounded self-correction loop (#13)** — the trust guarantee that makes #1 safe; unique advantage of a deterministic compiler; directly attacks the category's biggest complaint.
3. **AI explains what it changed + one-click undo of AI turns (#3/#4/#5)** — cheap (S) on top of the diff, massive trust/teaching value, and the safety net for experiments.
4. **AI suggests the next bricks (#6)** — kills blank-canvas paralysis for beginners; mostly a curated pattern library, low cost, high delight.
5. **Brick-scoped natural-language editing (#7) + voice input (#11)** — "make this enemy slower" on a selected brick matches the inspector UX users already know; voice is a cheap accessibility win with local STT.

Runner-up (if effort allows): playtest-by-AI auto-balance (#9) — high impact but L effort; ship the scripted-run MVP later.
