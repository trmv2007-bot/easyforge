# Sharing, Shipping & Distribution — Gap Analysis

**Product stance:** EasyForge exports a .efg project + a game file; the user shares it
themselves; we host nothing. Every recommendation either (a) produces an artifact the
user can upload anywhere, or (b) uses a zero-infrastructure free host as an optional,
non-account step.

## Landscape snapshot (what competitors do)

- **Construct 3** — Web (HTML5) export in free tier; export zip -> user uploads to any
  static host (recommends Netlify Drop); "Remote Preview" for LAN preview; itch.io
  tutorials.
- **GDevelop** — one-click publish to gd.games (their host); share button -> build ->
  server -> link + QR; unlimited local HTML5 exports; daily-limited one-click
  Android/iOS/desktop; pays creators credits for plays.
- **GB Studio** — Export ROM + Export Web (touch controls on mobile browsers -> zip ->
  upload to itch.io as HTML).
- **Buildbox** — Buildbox World app + Adbox; export directly to phone for playtest.
- **itch.io** — butler CLI + widget API: push up to 30GB, incremental uploads,
  per-channel analytics, iframe embed widget, OAuth API.
- **Newgrounds/CrazyGames/Poki** — curated portals with size gates (CrazyGames 50MB
  initial/250MB total; Poki ~5MB initial/8MB goal).
- **Rosebud/SoonLab/Caustic** — instant shareable browser link; Caustic bundles hosted
  leaderboards/cloud saves/analytics backend.

## Godot 4.x platform facts

- **Web export** needs matching templates; output is wasm + .pck; requires WebAssembly +
  WebGL 2.0; **Compatibility renderer only** (no Forward+/Mobile, no WebGPU).
  Single-thread export (4.3+) avoids COOP/COEP headers/cross-origin isolation — required
  so the game sits in an iframe with third-party embeds/ads. Audio in Sample mode.
  `user://` needs IndexedDB. Only HTTP/WebSocket(client)/WebRTC networking.
- **Size:** gzip/brotli on .wasm + .pck (wasm -> ~1/4); official web builds already use
  optimize=size; size_extra/LTO need a source build (violates no-fork).
- **Android export** needs JDK17 + SDK + NDK r28b + keystore (L effort). iOS needs
  macOS (infeasible on Windows). Consoles need licensing (out of scope).
- **Steam:** native .exe required, $100/game fee, 2-week Coming Soon, 5 screenshots —
  guidance only.

## Summary matrix

| # | Feature | Effort | Impact | Stance fit |
|---|---|---|---|---|
| 1 | Web (HTML5) export | M | 5/5 | local, free |
| 2 | Shareable play link (zero-infra host) | M | 5/5 | user's host |
| 3 | itch.io one-click publish + metadata | M | 4/5 | their account |
| 4 | Export size/load discipline | S | 3/5 | local |
| 5 | Mobile-browser support | M | 4/5 | local |
| 6 | In-app publishing guide | S | 3/5 | docs only |
| 7 | Playtest link + QR | S (needs 1-2) | 4/5 | |
| 8 | Embed widget | S | 2/5 | |
| 9 | Local high-score persistence | S | 3/5 | local |
| 10 | Cloud saves | L | 1/5 | CONFLICTS |
| 11 | Analytics (itch/local log) | S | 3/5 | |
| 12 | Ads / rev-share | L | 1/5 | opt-in only |
| 13 | Android export | L | 3/5 | heavy toolchain |
| 14 | iOS/console | XL | - | infeasible |
| 15 | Steam publishing | S (docs) | 1/5 | guidance only |

## Top 5 (ranked)

1. **Web (HTML5) export — "Publish to Web"** — the missing keystone; every competitor's
   headline feature; unblocked by Godot's official single-thread web templates
   (iframe/portal-safe, no COOP/COEP).
2. **One-click shareable play link** (anonymous/draft static-host deploy + copy/QR,
   honest "public link" wording) — converts the export dead-end into the friend-play
   loop; doubles as the playtesting mechanism.
3. **itch.io one-click publish via butler** with title/description/thumbnail metadata —
   gives every game a real page, embed widget, and free play analytics on the user's
   own account.
4. **Web export size + load-time discipline** (brotli .wasm/.pck, size badge vs portal
   caps) — S effort that protects every downstream share path.
5. **Mobile-browser support in web builds** (touch controls via existing remappable
   inputs, responsive scaling, incognito-safe storage) — half of the shared-link
   audience is on a phone.

## Explicitly deferred / rejected

Hosted leaderboards & cloud saves (stance conflict — local `user://` persistence is the
on-stance version), ads/rev-share (L effort, low fit, opt-in only), iOS/console
(infeasible on single Windows box), Steam integration (guidance only; $100 fee +
native-exe-only).
