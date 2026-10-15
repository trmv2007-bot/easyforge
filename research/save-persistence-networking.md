# Save, Persistence & Networking: Engine Benchmarks vs. EasyForge's No-Backend Stance

**Product context:** EasyForge — Windows no-code game maker, bricks → Godot 4.7, deterministic
compiler, BYOK AI, user never writes raw code, games ship LOCAL standalone with no netcode,
user shares exported files themselves. No backend server. The task also asks that the
no-hosting stance be honestly evaluated, not assumed sacred.

**Method:** Engine-doc/tutorial/community research (Godot 4.7 docs, Unity, Unreal, GameMaker,
GGRS/rollback literature, Steam/EOS docs, GDPR regulator guidance). Each feature is scored:
**Server-free?** (does it need infrastructure EasyForge doesn't have), **Effort** S/M/L,
**Beginner impact** (low/med/high — how much a no-code user gets, or breaks, if it's
missing/wrong), **Fit** (works as a brick / needs product care / violates the stance).

Legend: Effort S = a deterministic brick pair or a small stdlib codegen block; M = a
multi-brick system or nontrivial codegen; L = a project-grade feature.

---

## 1. Local save/load — JSON / binary file

- **What engines give beginners:** Godot's official docs teach JSON via `JSON.stringify` +
  `FileAccess` on `user://`; Unreal gives a `SaveGame` Blueprint parent class with
  `SaveGameToSlot`/`LoadGameFromSlot` nodes; Unity teaches JSON via `JsonUtility`; GameMaker
  gives one-call `game_save()`/`game_load()` "designed for beginners."
- **Godot specifics:** `user://` is writable in exports (unlike `res://`); `store_var`/
  `get_var` = compact binary. JSON is the recommended first format — debuggable in a text
  editor, hand-editable, and the failure mode (bad JSON) is recoverable.
- **Server-free?** YES — pure local file IO.
- **Effort:** S. **Beginner impact:** HIGH — without any save, every game is a session toy.
- **Fit:** Perfect brick. Compiler already generates GDScript; a `save_progress(dict)` +
  `load_progress()` brick pair is trivial. **Ship as the foundation brick.**

## 2. Save slots

- **What engines give beginners:** Godot community tutorials use `user://saves/slot_N.json`
  with per-slot `meta.json` (time saved, summary line, version) for the continue-menu;
  Unreal's slot-name + user-index API is the canonical model; GameMaker does `save_N.json`
  naming.
- **Server-free?** YES.
- **Effort:** S (slots are just filenames + a directory listing).
- **Beginner impact:** MED-HIGH — slots are what make a save system feel like a real game;
  without them, "continue" is confusing.
- **Fit:** Easy. Compiler can emit `SaveManager` autoload with a fixed slot count. Caveat:
  beginners will want slot metadata (screenshot-less is fine — time + summary line is enough).

## 3. Auto-save

- **What engines give beginners:** Godot tutorials wire `save_current_slot()` to
  `NOTIFICATION_WM_CLOSE_REQUEST` (quit) and timers; Unreal has `AsyncSaveGameToSlot` for
  large states so the game doesn't hitch; Unity best practice is background/async autosave.
- **Server-free?** YES.
- **Effort:** S as "save on exit / checkpoint"; M if async + periodic.
- **Beginner impact:** HIGH — beginners design short games where "quit and lose everything"
  is a rage-quit.
- **Fit:** Very good brick. Default: save on quit + on scene change. **Ship.**

## 4. Checkpoints

- Same machinery as auto-save triggered at a flag brick ("when player enters trigger zone,
  save to checkpoint slot").
- **Server-free?** YES. **Effort:** S. **Beginner impact:** HIGH for platformers/levels.
- **Fit:** Perfect brick. A "Checkpoint" entity + "Save" brick in the event sheet.

## 5. Game-state serialization (what to save, how)

- **What engines give beginners:** Godot docs teach the **"Persist" group** pattern — nodes in
  a group implement `save()`/`load()` returning a Dictionary; Unreal copies world state →
  SaveGame object → back on load; GameMaker teaches flattening `global.*` + inventory into a
  struct. Unity community wisdom: "identify what needs saving and when" — level number vs
  full inventory — and keep data/presentation separated, never serialize duplicate/cached
  data.
- **The no-code translation problem:** engines solve this with an *interface/attribute*
  (Unity `ISaveable`, Godot group callbacks). EasyForge has no user code, so the compiler must
  decide what is saveable. Feasible design: every brick's variables are schema'd; the compiler
  emits per-brick save/load automatically for declared "game data" variables (score, health,
  position, inventory, flags). Variables a user marks "session-only" (e.g. particle state) are
  excluded.
- **Server-free?** YES.
- **Effort:** M (the compile-time schema walk is the real work; runtime is trivial).
- **Beginner impact:** HIGH — and this is the single biggest differentiator: in raw engines
  this is where beginners stall ("which of my 40 variables do I save?"). EasyForge can
  genuinely be *better* than Unity here if the compiler emits save/load for every declared
  game variable.
- **Fit:** Core compiler feature. **Ship as "every game-data variable is automatically
  persisted."**

## 6. Player profiles

- **What engines give beginners:** Unreal separates "global unlocks" SaveGame classes from
  "playthrough" ones; GameMaker/Godot treat profile as just another file.
- Profile = name, unlocked content, stats, last-used slot index, settings. Profiles let a
  family share a machine.
- **Server-free?** YES. **Effort:** S-M.
- **Beginner impact:** MED. **Fit:** Good but second-wave; one profile with N slots covers 90%
  of no-code users. A "profile" is a subfolder of the saves dir.

## 7. Settings persistence (volume, fullscreen, keybinds)

- **What engines give beginners:** Unity `PlayerPrefs` (key-value, one call); Godot's right
  answer is **`ConfigFile`** (`user://settings.cfg`, INI-style, `get_value(section, key,
  default)` gives free fallbacks); GameMaker INI for flat settings. Key doctrine: settings are
  **per machine, not per slot** — keep them out of the save slot so deleting a save never
  resets the volume. Store volume linear 0–1, convert to dB when applying.
- **Server-free?** YES. **Effort:** S.
- **Beginner impact:** HIGH (volume sliders are expected in every shipped game; missing them
  reads as broken).
- **Fit:** Perfect brick. Compiler emits `user://settings.cfg` from the options menu.
  **Ship.**

## 8. Physics state persistence

- **What engines give beginners:** Nothing beginner-grade. Godot's own docs don't cover it;
  Godot Rapier (non-core addon) added a whole `RapierStateManager` with JSON/base64/bincode
  export — and even it "does not manipulate the scene tree." Godot-ECS projects have built-in
  snapshot systems. Engines leave this to advanced devs; per-body manual save (position +
  linear_velocity + angular_velocity + mode) is the common beginner workaround.
- **Honest assessment:** full physics-state save (every RigidBody mid-simulation) is an
  advanced feature. For a no-code tool, the honest scope is: save/restore per-body transform +
  velocity for bodies the user tagged, not a whole-space binary snapshot. Freezing-state save
  (pause and serialize at rest) is fine; mid-air rigid chaos restore is out of scope.
- **Server-free?** YES (local). **Effort:** L (full), M (per-body tagged subset).
- **Beginner impact:** LOW-MED (most no-code games are CharacterBody-based, not physics
  playgrounds — but "physics toy that doesn't save" is a classic complaint).
- **Fit:** Edge-case brick only. Auto-tag physics bodies whose position/velocity the user
  marked as game data; don't promise full-space serialization.

## 9. Local multiplayer — same-machine, split-screen / hotseat

- **What engines give beginners:** Godot: per-player input action sets (`p1_left`/`p2_left`),
  player-indexed spawn, and for split screen two `SubViewportContainer`s sharing one
  `World2D` so both cameras render the same world — GDQuest calls it "surprisingly simple."
  Hotseat (turn-based) needs no engine feature at all — just per-player UI state.
- **Server-free?** YES — zero networking. **Effort:** S for hotseat; M for split-screen
  (viewport/camera/world-sharing plumbing), but it's a *known recipe* the compiler could emit.
- **Beginner impact:** HIGH — couch co-op is a top request for no-code tool users; it needs no
  netcode and fits the no-hosting stance perfectly.
- **Fit:** Excellent. A "Player 2" flag + optional "split-screen camera" setting. The compiler
  emits the per-player input sets and viewport layout. **Ship — this is the biggest networking-
  adjacent win that violates nothing.**

## 10. LAN multiplayer with peer discovery

- **What engines give beginners:** Godot's `ENetMultiplayerPeer.create_server(port)/
  create_client(ip)` + `UPNP` class for automatic port forwarding; docs note LAN play via
  internal IP "just works", internet play needs manual UDP forwarding. Godot docs recommend
  async; community practice: `MultiplayerSpawner`/`MultiplayerSynchronizer`, authority per
  node, server-side validation.
- **No-code translation problem:** host/client/RPC/authority is *code-shaped* thinking —
  exactly what the no-code user is spared. A compiler could emit a fixed recipe (listen on
  fixed port, LAN scan, auto-authority), but "which variables sync?" is a per-game design
  question the user must express in bricks.
- **Server-free?** Technically yes for LAN (players host on their own machines), but it
  requires *the user's game* to include a networked mode — scope, QA, and firewall/UPNP
  flakiness come with it. It does not violate the no-hosting stance (no EasyForge servers),
  but it *does* violate the "games are LOCAL standalone" product line unless it ships as an
  opt-in "LAN mode" template.
- **Effort:** L. **Beginner impact:** HIGH demand, but high frustration when it breaks
  (firewalls, desyncs, "why can't my friend connect").
- **Fit:** Borderline. Recommend a scoped v1: same-network play with UDP broadcast discovery +
  deterministic-lite sync for a fixed variable set, clearly labeled beta. **Post-MVP.**

## 11. Rollback netcode

- **What engines give beginners:** Nothing — this is the domain of GGRS/GGPO (MIT, fighting
  games), requiring bit-exact determinism, fixed timestep, state snapshotting, input
  prediction, and desync detection. There is even a Rust GDNative GGRS binding for Godot, but
  it's a dev tool, not a beginner feature.
- **Server-free?** The netcode itself is P2P server-free, but it *demands determinism* — which
  collides with EasyForge's greatest strength: the deterministic bricks→GDScript compiler makes
  determinism *achievable* here in a way it isn't for most engines. Ironically, EasyForge is
  one of the few tools where rollback could be viable for fighting-game templates.
- **Effort:** L+. **Beginner impact:** Only for a narrow genre (1v1 fighters).
- **Fit:** Poor for general use; a "fighting game template" is the only sane scoping. Not for
  MVP.

## 12. Steam/EOS integration

- **What engines give beginners:** Unreal's OnlineSubsystem/OnlineServices with Steam
  achievements/leaderboards; Steam Cloud Auto-Cloud (declare file groups, zero code) or Cloud
  API; GodotSteam + a remote-storage wrapper for Godot. EOS Player Data Storage: free,
  cross-platform via Epic account, encrypted with a key the developer provides.
- **Server-free?** Mostly — it's Valve's/Epic's infra, not yours. But it means games require
  Steam/EOS presence, the export flow grows (appid, EOS product config), and "user exports
  the files and shares them" becomes "user needs Steam installed" for some players.
- **Effort:** M-L. **Beginner impact:** MED (achievements are a nice-to-have; cloud save
  matters only across the user's own machines).
- **Fit:** Partially in-tension with "share the exported game yourself" — a Steam-gated export
  contradicts the simple-share story. Achievements/cloud could be an optional export toggle
  later. **Post-MVP, evaluate honestly — this is where the no-hosting stance is actually
  tested: Steam Cloud is third-party hosting, but zero-ops zero-cost; EOS is the same with a
  better story.**

## 13. Analytics / telemetry

- **What engines give beginners:** Unity ecosystem defaults to GameAnalytics etc. — and the
  GDPR record is ugly: telemetry shipped before opt-in dialogs, persistent user IDs, regulators
  (Spanish AEPD/Belgian APD 2026 guidance) explicitly classify telemetry as personal data.
- **The server-free option is real:** local-first telemetry — collect to SQLite/JSONL on disk,
  zero network, with a first-launch privacy overlay and hard opt-out (see the Godot "Playtest
  & Launch Validator" toolkit pattern). The AEPD guidance literally recommends local-first as
  the default. Regulators call local-only processing "data protection by design."
- **Server-free?** Only in local form. Any network telemetry = a backend + privacy apparatus.
- **Effort:** M (local), L (networked + compliant).
- **Beginner impact:** HIGH for the *maker* (how do I know where players die?) if it exists;
  invisible if it doesn't.
- **Fit:** Local-first telemetry brick (opt-in, on-disk, user-exported via the same
  export-files flow) fits the stance beautifully. Networked analytics violates it. **Ship the
  local variant, skip the network variant.**

## 14. Replay systems

- **What engines give beginners:** Nothing built-in; the GDC literature shows two designs —
  per-frame world snapshots, or **input recording + deterministic resimulation** (record RNG
  seed + per-tick inputs; replay re-runs the sim). Emulator tooling (PyBoy) shows the ring-
  buffer rewind pattern.
- **Server-free?** YES — replays are files. The catch is determinism: a deterministic compiler
  makes input-recorded replays *far more* achievable than in raw engines (this is the same
  property that makes rollback possible).
- **Effort:** M (input-recording replay for deterministic bricks), L (snapshot replays for
  non-deterministic content).
- **Beginner impact:** MED — "watch my last run / share a replay" is a beloved feature, and
  shared replays are just small files — which fits "user shares files themselves" perfectly.
- **Fit:** Good post-MVP feature riding on the deterministic compiler. **Post-MVP, high
  thematic fit.**

## 15. Save migration & versioning

- **What engines give beginners:** GameMaker's best-practices guide is the clearest: always
  store a version number; detect old saves; migrate field-by-field. Unity community: "one
  version per data type, write version numbers early or old saves break." Godot tutorials
  include version in slot meta.json.
- **Honest assessment:** every engine community says beginners skip versioning and get
  burned. For a compiler tool this is *cheaper*: the compiler knows the schema of every game
  version, so it can emit migration functions automatically when the user's brick layout
  changes. This is a genuine no-code advantage.
- **Server-free?** YES. **Effort:** M (but mostly one-time compiler work that pays off
  forever).
- **Beginner impact:** MED initially, HIGH after the first "my players' saves broke" incident.
- **Fit:** Compiler feature — stamp every save with schema version, emit migrators on game
  change. **Ship with save v1; non-negotiable once games are shared.**

## 16. Encrypted saves

- **What engines give beginners:** Godot: `FileAccess.open_encrypted(path, mode, 32-byte key)`
  / `open_encrypted_with_pass()` — one call. GameMaker marketplace: `safe_ini_open(key)` or
  `safe_save` on ds_maps. Unity community is blunt: BinaryFormatter is *not* security and
  "will NOT prevent people from modifying your save data on their computers" — encryption is
  anti-casual-cheat, not anti-cheat.
- **Server-free?** YES. **Effort:** S (one flag on the save brick; the key is in the shipped
  game either way, so it's obfuscation — be honest in docs).
- **Beginner impact:** LOW-MED (matters for games with leaderboards/inventory where cheating
  ruins fun).
- **Fit:** Easy optional toggle ("protect save file") with honest documentation. **Ship as an
  option, small effort.**

## 17. Cloud sync via user-owned storage

- **What users actually do today:** Steam Cloud (auto-cloud file groups or Cloud API), or
  community tools — Ludusavi, GameSave Manager's "Sync & Link," OpenSave (P2P, no accounts,
  optional Drive/Dropbox/OneDrive/WebDAV mirror), OpenCloudSaves (rclone). The pattern: point
  the game's save folder at a synced folder (symlink or the game writing there directly).
- **Server-free?** If the *game* does it: only by embedding a cloud SDK (auth tokens in a
  shipped game = a backend relationship). The honest server-free version: **keep saves in a
  documented, stable folder so the user's existing Steam/OneDrive/Dropbox/Ludusavi setup syncs
  them** — zero code, zero hosting, fully compatible with the stance.
- **Effort:** S for the folder-contract approach; L for embedded sync (OAuth in game,
  conflict resolution — which every comparison notes is *the* unsolved part: cloud drives sync
  files, not save sessions).
- **Beginner impact:** MED (matters across the user's own machines).
- **Fit:** The folder-contract approach is *perfectly* aligned — document `user://saves/` as a
  stable path, done. Embedded sync violates the spirit. **Ship the folder contract, skip
  embedded sync.**

## 18. Local high-score persistence (EasyForge's current state)

- The existing high-score path is the seed of all of the above: a file in `user://` with a
  schema-versioned dict is save v1. Everything in this doc generalizes that one file.
- **Fit:** Keep, extend.

---

## Honest verdict on the no-hosting stance

The stance holds strongly for almost everything users actually feel:

- **Fully compatible, ship-grade:** save/load, slots, auto-save, checkpoints, settings,
  profiles, versioning, encryption, local telemetry, hotseat + split-screen, replay-via-
  determinism, save-folder contract for user-side cloud sync. None of these need a server and
  several (compiler-emitted serialization, auto-migration, deterministic replays) are
  *easier* in a no-code tool than in Unity/Unreal — because the schema is machine-known.
- **Stance-compatible but scope-risky:** LAN multiplayer (no EasyForge servers, but the game
  ships a networked mode — a big QA/firewall surface), Steam/EOS achievements + cloud
  (third-party hosting, zero ops, but Steam-gating exports tensions with "share files
  yourself").
- **Genuinely violated by:** networked analytics/telemetry backends, in-game embedded cloud
  sync with OAuth, dedicated servers, matchmaking. These require the infrastructure the stance
  deliberately avoids — and GDPR guidance makes network telemetry a compliance burden, not
  just a cost.
- **Interesting inversion:** rollback netcode and replays — traditionally expert-only —
  become *plausible* in EasyForge precisely because the compiler is deterministic. The stance
  that rules out servers doesn't rule out P2P; it just means any multiplayer story must be
  local-machine or LAN-first, with internet play only via user-chosen relays (the OpenSave
  room-code model), never EasyForge-run servers.

## TOP 5 RANKED (fit x effort x beginner impact, server-free first)

1. **Compiler-emitted game-state serialization + JSON save/load + slots + version stamp**
   (items 1+2+5+15, S-M) — the foundation everything else rides on; a genuine no-code
   advantage over hand-rolled engine saves.
2. **Auto-save + checkpoints + on-quit save** (3+4, S) — highest beginner-relief per line of
   compiler output; prevents "lost all progress" rage-quits.
3. **Settings persistence via ConfigFile** (7, S) — expected by every shipped game; trivially
   emitted from the options menu.
4. **Local same-machine multiplayer: hotseat + split-screen** (9, S/M) — biggest "wow" feature
   that requires zero networking and violates nothing; compiler can emit the known Godot
   viewport recipe.
5. **Local-first opt-in telemetry + replay-via-determinism + documented save-folder contract
   for user-side cloud sync** (13+14+17, M) — the post-v1 bundle that only a deterministic
   no-code tool can ship cheaply; each piece is server-free and aligned with the stance.

(Encrypted saves = honorable mention: one-call `FileAccess.open_encrypted_with_pass`, ship as
an optional toggle. LAN multiplayer = first item to honestly revisit after MVP, as an opt-in
beta template.)
