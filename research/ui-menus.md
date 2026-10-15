# UI/UX & Menu Systems — Gap Analysis for EasyForge

EasyForge's compiled games currently ship a **single generated HUD**: a full-rect
`Control` with two hand-placed `Label`s (ScoreLabel top-left, MessageLabel center)
that poll `GameState` every frame, plus a win/lose string
(`src/compiler/compiler.gd`, `_build_hud()`). There is no widget library, no
screen/flow system, no theme, no input navigation — the user's only authoring
surface for look-and-feel is brick parameters (background theme palette, "grass/
stone/pink" color themes) and a scene sky theme preset. Nothing else touches UI.

World-class engines give beginners most of the following **out of the box or via
one-line config**. Ranked here by impact-per-effort against EasyForge's
constraints (Godot 4.7 official, deterministic compiler, no raw code, local
standalone, primitive+procedural assets only).

Format per feature: **one-liner · Effort (S/M/L) · Beginner impact · Constraint fit**

---

## 1. Widget library (buttons, sliders, toggles, dropdowns, scroll views)

**What the world does.** Godot ships the full set natively — Button, CheckBox,
OptionButton, Slider, ScrollContainer, TabContainer, ItemList (docs: "Using
Containers"); Unity ships them as Canvas/UI Toolkit prefabs with a designer;
Construct has button/dialog behaviors. In all cases the beginner's first act is
"drag a button, hook its event."

**One-liner:** A fixed library of ~10 compiler-emitted widget nodes (Button,
Toggle/CheckBox, Slider, OptionButton, PanelContainer, ScrollContainer, Tab
bar, ProgressBar/TextureProgress, ItemList/grid, LineEdit) emitted as one
deterministic GDScript factory, so any screen can be composed from them without
users touching Control nodes.
**Effort:** M · **Beginner impact:** Very high — these are the vocabulary of
every game UI · **Constraint fit:** Perfect — Godot-native nodes, pure function
of brick params, no runtime code authored by user.

## 2. Layout system (anchors + containers, responsive)

**What the world does.** Godot anchors ("fractions of parent rect") + containers
(VBox/HBox/Grid/Margin/Center/Panel/Scroll/AspectRatio) are the standard answer;
GDQuest calls containers "like CSS flex/grid." Unity's UI Toolkit auto-layout and
uGUI Canvas Scaler do the same job. Every engine offers "responsive by default."

**One-liner:** Compiler always wraps UI in containers + anchor presets
(`PRESET_FULL_RECT`, `TOP_WIDE`, safe-area margins) and scales via
`content_scale_mode`, so a game looks right at any window size — the current HUD
is hand-positioned pixels that break at non-1920×1080.
**Effort:** S-M (retrofit the existing HUD + bake into every new screen) ·
**Beginner impact:** Very high (their exported game won't look broken on a
friend's screen) · **Constraint fit:** Perfect — deterministic preset math.

## 3. Menu screen system (main / pause / settings / game-over / credits)

**What the world does.** GameMaker teaches menus as "new Room + Sequence +
buttons" (official Fire Jump tutorial). RPG Maker ships fully built title,
menu, item, skill, save, options screens; Unite even lets you toggle menu items
on/off. Godot has no built-in menus — beginners rebuild them per project
(hence the genre of "pause menu in 5 minutes" tutorials). This is the single
most copy-pasted beginner project in Godot.

**One-liner:** A "Screens" system: 5 compiler-generated screens (Title, Pause,
Settings, Game Over, Credits) wired to a tiny screen-stack manager
(show/hide/pause-aware Process Mode, Esc/Start to open), toggled by bricks
("has main menu", "has pause menu") — users get a finished game arc, not a
sketch.
**Effort:** M-L (screens themselves are S each; the stack + pause plumbing is
the work) · **Beginner impact:** Very high — the difference between "toy
prototype" and "shareable game" · **Constraint fit:** Perfect — pure Control
scenes + one autoload, all compiler-emitted.

## 4. HUD design kit (health bars, inventories, minimaps, quest logs)

**What the world does.** Unity/RPG Maker ship health/inventory/quest components;
Godot gives you TextureProgress + GridContainer + SubViewport minimap to
assemble yourself.

**One-liner:** HUD bricks — "Health Bar" (hearts or bar, max value, colors),
"Inventory grid" (slots × icons, add/remove from GameState), "Minimap"
(SubViewport + camera zoom), "Quest/objective list" (text lines, checkboxes) —
each a declarative brick whose params compile to widget nodes bound to
GameState, replacing today's score-only HUD.
**Effort:** M per widget type, S each once the widget factory exists ·
**Beginner impact:** High — "my platformer with 3 hearts" reads as a real game ·
**Constraint fit:** Perfect — data-driven, deterministic, primitive shapes only.

## 5. Theming & styling (Theme resource, StyleBox, 9-slice, skins)

**What the world does.** Godot's Theme resource (colors/fonts/StyleBox per
control type) + StyleBoxTexture 9-slice is the documented way to skin UI; RPG
Maker's "windowskin" is a single image swap for every menu; Unity USS/style
sheets do the same. Beginners expect "pick a look, done."

**One-liner:** Compiler generates one shared `Theme` resource (colors, font
size, rounded StyleBoxFlat panels, hover/press states) driven by a "UI Style"
brick param (flat / pixel / neon / soft) — procedural StyleBoxFlat keeps the
"primitives only" constraint while giving every button a consistent look; add
9-slice later when sprite assets land.
**Effort:** S-M (StyleBoxFlat path) / M (9-slice needs generated panel texture
— still procedural via StyleBoxTexture on a generated image) ·
**Beginner impact:** Very high — cheapest "polished, not default Godot gray"
signal · **Constraint fit:** Good — StyleBoxFlat/Line/Texture are all
textureless-capable; 9-slice can use a compiler-drawn border image.

## 6. Localization & text handling (TranslationServer, plurals, pseudoloc)

**What the world does.** RPG Maker has built-in translation; Unity has
localization packages; Godot has TranslationServer — labels/buttons
auto-translate when text matches a key, CSV imports languages, `tr_n()` handles
plurals (4.6+ supports `?plural` in CSV), and pseudolocalization expansion
(+30% string length) is a TranslationDomain property.

**One-liner:** A "Languages" project setting + "Language" in a Settings
screen: compiler emits a keyed-string table and the Settings dropdown calls
`TranslationServer.set_locale()`; UI text stretches via containers (ties to #2)
so German/Japanese don't clip.
**Effort:** S (CSV + locale call) / M (UI-wrapping audit) ·
**Beginner impact:** Medium-high — "my game in 5 languages" is a badge of
pride for hobbyists · **Constraint fit:** Perfect — engine feature, no assets.

## 7. Screen transitions & UI animations (fade/wipe/slide, hover, tweens)

**What the world does.** GameMaker's official tutorial teaches fade transitions
via Sequences; Godot: Tween/AnimationPlayer alpha tweens (dev.to "5 scene
transition effects"); RPG Maker Unite has "start from a fadeout" as a built-in
project setting.

**One-liner:** A "Transition" param (none / fade / slide / pixelate, duration +
easing) on every screen brick, compiled to a shared Tween autoload — plus
button hover/press scale tweens baked into the generated Theme, so the whole
game feels animated with zero user effort.
**Effort:** S (fade Tween is ~10 lines) / M (menu of effects) ·
**Beginner impact:** Very high — animation is the #1 "juice" tell ·
**Constraint fit:** Perfect.

## 8. Modal dialogs (confirm, message boxes, popups)

**What the world does.** Construct's SmartUI dialog behavior (modal stacking,
auto-focus first element, close button); Unreal CommonUI activatable widgets
with Back handlers; Unity has no built-in modal, everyone builds one.

**One-liner:** A "Dialog" brick — title + message + OK/Cancel buttons, modal
(semi-transparent full-rect scrim that blocks lower UI), compiled to one
PanelContainer scene + a `show_dialog(text, confirm_label)` helper; used by
"Are you sure you want to quit?" and event messages.
**Effort:** S · **Beginner impact:** Medium-high — instant perceived
professionalism, blocks accidental taps · **Constraint fit:** Perfect.

## 9. UI input navigation: keyboard + gamepad + mouse

**What the world does.** Unreal CommonUI is the gold standard: auto D-pad
navigation, focus restore when screens close, input-mode detection (gamepad vs
mouse), back-stack. Godot: focus neighbors + `ui_*` actions work out of the
box but need wiring; the community `godot-menu-system` repo exists precisely
because it's per-project work.

**One-liner:** Compiler emits focus-ready screens: every Button in a
`VBoxContainer` gets automatic D-pad/arrow navigation, first button
`grab_focus()` on show, Esc/B mapped to Back, and a highlighted focus stylebox
— one shared "UINav" recipe, so gamepad players can use every generated menu.
**Effort:** S-M (focus flags + nav actions + focus theme) ·
**Beginner impact:** High — makes games playable on controllers with no user
action · **Constraint fit:** Perfect — Godot focus system is native.

## 10. Data-binding (UI reflects game state automatically)

**What the world does.** Unity 6 runtime data binding (MVVM, two-way bindings,
"health bar updates without script logic"); Unreal ViewModel/MVVM plugin;
Godot has no binding layer — you connect signals or poll.

**One-liner:** Formalize the existing implicit binding: widgets declare
`bind: GameState.health / GameState.coins / GameState.score` in brick params,
and the compiler emits signal-connected updater code (one `_update` method per
screen wired to GameState's changed signals) instead of today's per-frame
polling HUD — deterministic output, no polling cost.
**Effort:** S-M (GameState already exists and is the natural single source) ·
**Beginner impact:** High — "score goes up when I touch a coin" is the first
magic moment · **Constraint fit:** Perfect — codegen of signal connections.

## 11. Procedural UI (widgets + skins generated from data)

**What the world does.** Nothing in the big five generates UI procedurally —
this is EasyForge's *edge*, not a gap: because the compiler already emits
scenes from brick graphs, it can generate whole screens from one "menu" brick
(Unity/RPG Maker require hand-authoring or heavy assets).

**One-liner:** "Screen templates": one brick param set (`layout: vertical |
grid | hud_row`, items: [...]) emits a complete, styled, navigable screen —
turning what is a multi-hour manual job in Godot into a brick click; same
machinery as #3 but exposed as a composable primitive.
**Effort:** M (once widget factory + theme exist, near-free per template) ·
**Beginner impact:** Very high — this is the whole product thesis ·
**Constraint fit:** Perfect — deterministic codegen, primitive StyleBoxes only.

## 12. Touch-friendly UI (target sizes, safe areas, thumb zones)

**What the world does.** Apple HIG 44pt / Material 48dp minimum targets, 8dp
gaps, primary actions in the thumb arc, safe-area insets (notches, gesture
bars) — the published consensus for mobile game UX.

**One-liner:** Bake the rules into the compiler's layout constants: buttons
≥48×48 logical px with ≥8px gaps, actions anchored to the lower thumb zone,
safe-area margins via `DisplayServer.get_display_safe_area()`, so an exported
game is tablet/touch-viable by default with zero user decisions.
**Effort:** S (constants + margins) · **Beginner impact:** Medium (desktop-first
users won't notice; mobile sharers will) · **Constraint fit:** Perfect —
pure layout math.

## 13. Accessibility in UI (contrast, scalable text, colorblind-safe, captions)

**What the world does.** Xbox Accessibility Guidelines: 4.5:1 text contrast
(7:1 high-contrast mode), resizable text to 200%, never color-alone for state,
subtitle options, adjustable UI scale — increasingly table stakes for shipped
games and platform certification.

**One-liner:** Generated defaults that are accessible on day one: high-contrast
text outlines/shadows, UI-scale setting (all sizes in one theme constant
block), state conveyed by icon+text+color not color alone, and a "Text Size"
Settings slider — cheap to emit, and a real differentiator for a beginner
tool whose users' games will be judged by players, not cert bodies.
**Effort:** S-M · **Beginner impact:** Medium-high (invisible when done right,
fatal when wrong) · **Constraint fit:** Perfect — theme constants + scale
settings.

---

## Cross-cutting observations

- **Everything above is a *deterministic codegen* problem, not an engine
  problem.** Godot 4.7 already contains every node, focus behavior, theme
  mechanism, TranslationServer call and tween primitive required. EasyForge's
  compiler emits scene trees as strings — each feature maps to "emit this
  parameterized subtree," which is exactly the architecture already proven by
  `_build_hud()`.
- **The GameState autoload is already the binding source.** Today's HUD polls
  it per-frame; extending GameState (health, inventory, objectives) + emitting
  signal-bound widgets covers #4 and #10 together.
- **Dependency order that minimizes effort:** widget factory (1) → theme (5) →
  screens/menus (3) → transitions (7) → HUD kit (4) → dialogs (8) → nav (9) →
  localization (6) → accessibility (13). 1+5 are prerequisites for nearly
  everything else; 3 is where most of the user-visible value lands.
- **Highest risk:** focus navigation (9) regressing across generated screens —
mitigate with one shared UINav recipe + a smoke test that Tab-walks each
  screen.

---

## TOP 5 (ranked by impact ÷ effort for a no-code beginner tool)

1. **Screen/Menu system (main, pause, settings, game-over, credits) with
   screen-stack + Esc/Start handling** — the gap between "demo" and "game";
   every world-class tool ships or teaches this; Godot beginners rebuild it by
   hand every project. M-L effort, highest user-visible payoff.
2. **Widget library + layout defaults (containers, anchor presets,
   ≥48px targets, responsive scale)** — the foundation every other UI feature
   composes on; S-M and unblocks 4, 8, 11, 12. Fixes today's fixed-pixel HUD
   that breaks on other window sizes.
3. **Procedural UI: one "Screen" brick → styled, navigable, data-bound
   screen** — EasyForge's structural advantage over Unity/Godot/RPG Maker
   (they require hand authoring); turns the compiler's existing strength into
   a user-visible feature. M effort, huge ceiling.
4. **Theming/UI Style presets + transitions/animations (fade/slide, hover
   tweens)** — cheapest polish jump ("not default gray Godot"); combined S-M.
5. **Data-binding via GameState signals (score/health/inventory/objectives →
   widgets) + HUD kit (health bar, inventory, quest log)** — makes the first
   magic moment real and stops the per-frame polling HUD; S-M once GameState
   exists.
