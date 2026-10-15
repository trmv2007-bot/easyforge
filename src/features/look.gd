extends Node
## look — one 'Look' brick that swaps the whole scene's Environment resource for
## a curated cinematic grade.
##
## WHAT IT ADDS (3D)
##   Replaces the compiler's default WorldEnvironment with one Environment that
##   bundles bloom (glow), ACES filmic tonemapping, and brightness/contrast/
##   saturation adjustment — the four knobs that turn a bare prototype into
##   something that reads as a shipped game. Also re-colours the DirectionalLight3D
##   named SunLight so the lighting matches the grade, and builds a Sky +
##   ProceduralSkyMaterial exactly like compiler.gd's _build_sky does.
##   If there is no SunLight yet (the compiler's _finalize runs after pass 2), the
##   grade is applied to it later through a tiny deferred node, so ordering never
##   produces a mismatched sun.
##
## WHAT IT ADDS (2D)
##   A CanvasModulate named LookModulate carrying the preset tint, so the grade is
##   visible in a 2D game. NO WorldEnvironment is added in 2D (there is no 3D
##   viewport to grade). Optional fog param paints a dark ColourRect overlay
##   across the viewport.
##
## TONEMAPPER RULE (from research — non-negotiable)
##   Never Environment.TONE_MAPPER_LINEAR. Linear clips highlights and makes HDR
##   lighting blow out to flat white, per Godot's own docs. Every preset uses
##   ACES_FILMIC (or ACES where a preset asks for the gentler curve).
##
## HONESTY NOTE ON VIGNETTE
##   Godot 4 has no built-in vignette on Environment. In 3D we therefore do NOT
##   fake one — the vignette param only darkens the 2D tint overlay. In 2D it
##   draws a real edge-darkening frame (four solid ColourRects on a CanvasLayer),
##   which is an honest vignette because it is drawn over the rendered output.
##
## DETERMINISM
##   Everything here is derived from brick params and fixed preset tables. No
##   randf(), no filesystem, no wall-clock. The same brick always compiles to the
##   same Environment.
##
## INTEGRATOR NOTES (no edit needed in this file):
##   brick.gd needs a "look" kind with these params:
##     preset      choice [cinematic, neon, pastel, noir, warm, cold, space, dreamy]
##     bloom       number 0.0..2.0   (default 0.35)
##     saturation  number 0.0..2.0   (default 1.0)
##     contrast    number 0.5..2.0   (default 1.0)
##     brightness  number 0.5..2.0   (default 1.0)
##     vignette    bool             (default true)
##     ssao        bool             (default false — Forward+ only, harmless elsewhere)
##     fog         bool             (default false)
##     apply_2d    bool             (default true — in 2D, add the CanvasModulate)
##   A slider only overrides the preset when the user moved it off the default.

# The global script class cache does not contain FeatureCtx, so the bare
# identifier is NOT in scope in a feature module. Preload it explicitly — this
# is the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

# Node names this module owns. Shared with nothing else, so they are safe to
# match on — except WorldEnvironment/SunLight, which the COMPILER also creates
# (see _PRESETS note below): those two are replaced, never stacked.
const ENV_NAME := "WorldEnvironment"
const SUN_NAME := "SunLight"
const MODULATE_NAME := "LookModulate"
const GRADE_NAME := "LookGrade"        # the deferred sun re-colour driver (3D)
const FOG_NAME := "LookFog"            # 2D fog overlay
const VIGNETTE_NAME := "LookVignette"  # 2D vignette frame

# Preset defaults the user's sliders are compared against. A value equal to one
# of these is treated as "untouched" and the preset's own value is used instead.
const DEF_BLOOM := 0.35
const DEF_SAT := 1.0
const DEF_CONTRAST := 1.0
const DEF_BRIGHTNESS := 1.0

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

func register(reg) -> void:
	if reg == null:
		return
	# Pass 2. The Look brick is a scene-level grade; it must run in the same
	# pass the Sky brick runs in (both want to own the WorldEnvironment), and
	# _finalize adds the default env AFTER this pass — so a plain pass-2 build
	# would stack a second WorldEnvironment. The deferred driver in
	# _install_grade cleans that up at the end of the frame instead.
	reg.register("look", _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	var p := _p(b)
	var preset_name := _preset_name(p)
	var cfg := _preset(preset_name)

	var bloom := _slider(_num(p, "bloom", DEF_BLOOM), DEF_BLOOM, 0.0, 2.0)
	if bloom == DEF_BLOOM and cfg.has("bloom"):
		bloom = float(cfg["bloom"])
	var sat := _slider(_num(p, "saturation", DEF_SAT), DEF_SAT, 0.0, 2.0)
	if sat == DEF_SAT and cfg.has("saturation"):
		sat = float(cfg["saturation"])
	var contrast := _slider(_num(p, "contrast", DEF_CONTRAST), DEF_CONTRAST, 0.5, 2.0)
	if contrast == DEF_CONTRAST and cfg.has("contrast"):
		contrast = float(cfg["contrast"])
	var brightness := _slider(_num(p, "brightness", DEF_BRIGHTNESS), DEF_BRIGHTNESS, 0.5, 2.0)
	if brightness == DEF_BRIGHTNESS and cfg.has("brightness"):
		brightness = float(cfg["brightness"])
	var vignette := _bool(p, "vignette", true)
	var ssao := _bool(p, "ssao", false)
	var fog := _bool(p, "fog", false)
	var apply_2d := _bool(p, "apply_2d", true)

	var is_3d := _is_3d(ctx, root)

	if is_3d:
		_build_3d(root, cfg, bloom, sat, contrast, brightness, vignette, ssao, fog)
	else:
		_build_2d(root, cfg, vignette, fog, apply_2d)

# ---------------------------------------------------------------------------
# 3D — one Environment, one sun, nothing else
# ---------------------------------------------------------------------------

func _build_3d(root: Node, cfg: Dictionary, bloom: float, sat: float,
		contrast: float, brightness: float, vignette: bool, ssao: bool,
		fog: bool) -> void:
	# Replace any WorldEnvironment already here (the compiler's default, or a
	# Sky brick's) rather than stacking a second one.
	_drop_children(root, ENV_NAME)
	_drop_children(root, SUN_NAME)

	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = cfg["sky"]
	psm.sky_horizon_color = cfg["horizon"]
	psm.ground_bottom_color = cfg["ground"]
	psm.ground_horizon_color = cfg["horizon"]
	sky.sky_material = psm

	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = cfg["ambient"]
	# THE RULE: never TONE_MAPPER_LINEAR (=0). Linear clips highlights and makes
	# HDR lighting blow out to flat white, per Godot's own docs. Every preset
	# ships a filmic/ACES curve; Godot 4.7 exposes FILMIC(2) and ACES(3), there
	# is no ACES_FILMIC — ACES is the filmic curve we want.
	env.tonemap_mode = int(cfg["tonemapper"])

	# bloom (glow)
	env.glow_enabled = bloom > 0.0
	env.glow_intensity = bloom
	env.glow_strength = clampf(0.6 + bloom * 0.8, 0.2, 2.0)
	env.glow_bloom = clampf(0.05 + bloom * 0.15, 0.0, 0.35)
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.0

	# colour grade. Kept enabled even with unit values so the adjustments the
	# user did make are not silently discarded.
	env.adjustment_enabled = true
	env.adjustment_brightness = brightness
	env.adjustment_contrast = contrast
	env.adjustment_saturation = sat

	# vignette: Godot has no built-in vignette on Environment. We deliberately
	# do NOT fake one in 3D — the param is only consumed by the 2D path, where
	# a real edge-darkening overlay is drawn over the rendered output.
	# (vignette is intentionally unused here; see the 2D branch below.)

	if ssao:
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 2.0
	if fog:
		env.fog_enabled = true
		env.fog_light_color = cfg["horizon"]
		env.fog_density = 0.015

	var we := WorldEnvironment.new()
	we.name = ENV_NAME
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = SUN_NAME
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_color = cfg["sun"]
	sun.light_energy = cfg["sun_energy"]
	sun.shadow_enabled = true
	root.add_child(sun)

	# The compiler's _finalize adds its OWN default WorldEnvironment + SunLight
	# after this pass (in 3D it always does). Those two run after us and would
	# either stack a second environment or re-colour the sun. Re-apply the grade
	# at the end of the frame instead, once everything the compiler adds exists.
	_add_deferred_driver(root, cfg, bloom, sat, contrast, brightness, ssao, fog)

## Install a tiny deferred node that re-runs the 3D grade once the compiler's
## _finalize has had its turn. Idempotent: it replaces environments/suns rather
## than adding to them, so running twice is the same as running once.
func _add_deferred_driver(root: Node, cfg: Dictionary, bloom: float, sat: float,
		contrast: float, brightness: float, ssao: bool, fog: bool) -> void:
	if root.get_node_or_null(GRADE_NAME) != null:
		return
	var driver := Node.new()
	driver.name = GRADE_NAME
	var src := _driver_source(cfg, bloom, sat, contrast, brightness, ssao, fog)
	if FeatureCtx.attach_script(driver, src) != OK:
		push_error("[look] deferred grade driver failed to compile")
		return
	root.add_child(driver)

func _driver_source(cfg: Dictionary, bloom: float, sat: float,
		contrast: float, brightness: float, ssao: bool, fog: bool) -> String:
	var s := ""
	s += "extends Node\n"
	s += "# Generated by EasyForge from a 'Look' brick.\n"
	s += "# One Environment for the whole scene: bloom + ACES tonemapping +\n"
	s += "# colour grade. Runs after the frame's build so it can replace the\n"
	s += "# compiler's default environment and re-colour the default sun.\n"
	s += "var _done := false\n"
	s += "\n"
	s += "func _process(_delta: float) -> void:\n"
	s += "\tif _done:\n"
	s += "\t\treturn\n"
	s += "\t_done = true\n"
	s += "\tvar root := get_parent()\n"
	s += "\tif root == null:\n"
	s += "\t\treturn\n"
	s += "\tvar env := _env_resource()\n"
	s += "\t_apply_env(root, env)\n"
	s += "\t_apply_sun(root)\n"
	s += "\n"
	s += "func _env_resource() -> Environment:\n"
	s += "\tvar e := Environment.new()\n"
	s += "\tvar sky := Sky.new()\n"
	s += "\tvar psm := ProceduralSkyMaterial.new()\n"
	s += "\tpsm.sky_top_color = %s\n" % _color(cfg["sky"])
	s += "\tpsm.sky_horizon_color = %s\n" % _color(cfg["horizon"])
	s += "\tpsm.ground_bottom_color = %s\n" % _color(cfg["ground"])
	s += "\tpsm.ground_horizon_color = %s\n" % _color(cfg["horizon"])
	s += "\tsky.sky_material = psm\n"
	s += "\te.background_mode = Environment.BG_SKY\n"
	s += "\te.sky = sky\n"
	s += "\te.ambient_light_source = Environment.AMBIENT_SOURCE_SKY\n"
	s += "\te.ambient_light_energy = %f\n" % float(cfg["ambient"])
	s += "\te.tonemap_mode = %d\n" % int(cfg["tonemapper"])
	s += "\te.glow_enabled = %s\n" % ("true" if bloom > 0.0 else "false")
	s += "\te.glow_intensity = %f\n" % bloom
	s += "\te.glow_strength = %f\n" % clampf(0.6 + bloom * 0.8, 0.2, 2.0)
	s += "\te.glow_bloom = %f\n" % clampf(0.05 + bloom * 0.15, 0.0, 0.35)
	s += "\te.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT\n"
	s += "\te.glow_hdr_threshold = 1.0\n"
	s += "\te.adjustment_enabled = true\n"
	s += "\te.adjustment_brightness = %f\n" % brightness
	s += "\te.adjustment_contrast = %f\n" % contrast
	s += "\te.adjustment_saturation = %f\n" % sat
	if ssao:
		s += "\te.ssao_enabled = true\n"
		s += "\te.ssao_radius = 1.0\n"
		s += "\te.ssao_intensity = 2.0\n"
	if fog:
		s += "\te.fog_enabled = true\n"
		s += "\te.fog_light_color = %s\n" % _color(cfg["horizon"])
		s += "\te.fog_density = 0.015\n"
	s += "\treturn e\n"
	s += "\n"
	s += "func _apply_env(root: Node, env: Environment) -> void:\n"
	s += "\t# drop every WorldEnvironment (ours + the compiler's default) ...\n"
	s += "\tfor ch in root.get_children():\n"
	s += "\t\tif ch is WorldEnvironment:\n"
	s += "\t\t\troot.remove_child(ch)\n"
	s += "\t\t\tch.free()\n"
	s += "\tvar we := WorldEnvironment.new()\n"
	s += "\twe.name = \"%s\"\n" % ENV_NAME
	s += "\twe.environment = env\n"
	s += "	root.add_child(we)\n"
	s += "\n"
	s += "func _apply_sun(root: Node) -> void:\n"
	s += "	# The compiler's _make_sun() also runs in _finalize, i.e. AFTER this\n"
	s += "	# pass, so the sun here may be the compiler's un-graded one. Replace\n"
	s += "	# every DirectionalLight3D with the grade's own sun (remove + free,\n"
	s += "	# then add ours) — exactly the replace-not-stack rule the Sky brick\n"
	s += "	# follows for the environment.\n"
	s += "	for ch in root.get_children():\n"
	s += "		if ch is DirectionalLight3D:\n"
	s += "			root.remove_child(ch)\n"
	s += "			ch.free()\n"
	s += "	var light := DirectionalLight3D.new()\n"
	s += "	light.name = \"%s\"\n" % SUN_NAME
	s += "	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)\n"
	s += "	light.light_color = %s\n" % _color(cfg["sun"])
	s += "	light.light_energy = %f\n" % float(cfg["sun_energy"])
	s += "	light.shadow_enabled = true\n"
	s += "	root.add_child(light)\n"
	return s

# ---------------------------------------------------------------------------
# 2D — a CanvasModulate tint (and, if asked, fog + a real vignette frame)
# ---------------------------------------------------------------------------

func _build_2d(root: Node, cfg: Dictionary, vignette: bool, fog: bool,
		apply_2d: bool) -> void:
	# No WorldEnvironment in 2D: there is no 3D viewport to grade.
	if not apply_2d:
		return
	var cm := CanvasModulate.new()
	cm.name = MODULATE_NAME
	var tint: Color = cfg["tint"]
	if vignette:
		# Darken toward the edges by letting the tint sit slightly darker; a
		# full vignette needs the overlay below.
		cm.color = tint * 0.95
	else:
		cm.color = tint
	root.add_child(cm)

	if fog:
		_drop_children(root, FOG_NAME)
		var layer := CanvasLayer.new()
		layer.name = FOG_NAME
		var rect := ColorRect.new()
		rect.color = _fog_color(cfg)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(rect)
		root.add_child(layer)

	if vignette:
		_drop_children(root, VIGNETTE_NAME)
		var layer := CanvasLayer.new()
		layer.name = VIGNETTE_NAME
		var shade: Color = Color(0, 0, 0, 0.55)
		# top, bottom, left, right edge bars — a real darkening of the edges
		for i in range(4):
			var bar := ColorRect.new()
			bar.color = shade
			bar.set_anchors_preset(Control.PRESET_FULL_RECT)
			match i:
				0: bar.anchor_bottom = 0.14   # top
				1: bar.anchor_top = 0.86      # bottom
				2: bar.anchor_right = 0.14    # left
				3: bar.anchor_left = 0.86     # right
			layer.add_child(bar)
		root.add_child(layer)

# ---------------------------------------------------------------------------
# Preset table
# ---------------------------------------------------------------------------

func _preset_name(p: Dictionary) -> String:
	var v := _str(p, "preset", "cinematic")
	match v:
		"cinematic", "neon", "pastel", "noir", "warm", "cold", "space", "dreamy":
			return v
		_:
			return "cinematic"

func _preset(name: String) -> Dictionary:
	match name:
		"cinematic":
			# teal-orange: the workhorse "shot on a camera" grade
			return {"sky": Color("#1b3a4b"), "horizon": Color("#ff8c42"),
				"ground": Color("#2b2320"), "sun": Color("#ffb27a"),
				"sun_energy": 1.15, "ambient": 0.6, "tint": Color("#e8d5c4"),
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"neon":
			# magenta/cyan, high bloom — bloom pushed up by the preset itself
			return {"sky": Color("#12002b"), "horizon": Color("#ff2bd6"),
				"ground": Color("#0a0014"), "sun": Color("#5df6ff"),
				"sun_energy": 1.0, "ambient": 0.55, "tint": Color("#c8a8ff"),
				"bloom": 0.9, "saturation": 1.3,
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"pastel":
			# soft pink/blue. LINEAR is defensible for this flat look but we
			# still ship ACES_FILMIC for consistency and predictable clamping.
			return {"sky": Color("#ffd6e8"), "horizon": Color("#cfe8ff"),
				"ground": Color("#e8d8f0"), "sun": Color("#fff0f6"),
				"sun_energy": 1.2, "ambient": 0.8, "tint": Color("#ffdcec"),
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"noir":
			# desaturated toward near-mono; saturation forced to 0.3 unless
			# the user deliberately moved the slider.
			return {"sky": Color("#1a1a1a"), "horizon": Color("#4a4a4a"),
				"ground": Color("#0d0d0d"), "sun": Color("#e8e8e8"),
				"sun_energy": 1.05, "ambient": 0.5, "tint": Color("#8c8c8c"),
				"saturation": 0.3, "contrast": 1.25,
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"warm":
			return {"sky": Color("#6b3410"), "horizon": Color("#ffb347"),
				"ground": Color("#3a2312"), "sun": Color("#ffc266"),
				"sun_energy": 1.25, "ambient": 0.65, "tint": Color("#ffd9a8"),
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"cold":
			return {"sky": Color("#0d1b3a"), "horizon": Color("#7aa8d8"),
				"ground": Color("#0a1020"), "sun": Color("#cfe2ff"),
				"sun_energy": 1.05, "ambient": 0.6, "tint": Color("#cfe0f5"),
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"space":
			# near black, low ambient: stars read as stars
			return {"sky": Color("#000008"), "horizon": Color("#1a1a3e"),
				"ground": Color("#000004"), "sun": Color("#dfe4ff"),
				"sun_energy": 0.75, "ambient": 0.35, "tint": Color("#9aa4d8"),
				"tonemapper": Environment.TONE_MAPPER_ACES}
		"dreamy":
			return {"sky": Color("#d8c8ff"), "horizon": Color("#ffe8f8"),
				"ground": Color("#e0d0ff"), "sun": Color("#fff0fb"),
				"sun_energy": 1.15, "ambient": 0.8, "tint": Color("#e6dcff"),
				"tonemapper": Environment.TONE_MAPPER_ACES}
		_:
			return _preset("cinematic")

func _fog_color(cfg: Dictionary) -> Color:
	var c: Color = cfg["horizon"]
	return Color(c.r, c.g, c.b, 0.18)

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

## Remove every direct child of `root` with the given name (Godot auto-renames
## duplicates to @Class@N, so a name match alone would miss a second copy).
func _drop_children(root: Node, node_name: String) -> void:
	var victims := []
	for ch in root.get_children():
		if str(ch.name) == node_name or str(ch.name).begins_with(node_name + "@"):
			victims.append(ch)
	for v in victims:
		if v.get_parent() != null:
			v.get_parent().remove_child(v)
		v.free()

func _color(c: Color) -> String:
	return "Color(%f, %f, %f, %f)" % [c.r, c.g, c.b, c.a]

# ---------------------------------------------------------------------------
# Param helpers — same defensive contract as FeatureCtx, so a brick with a
# missing/null/wrong-typed params dict still compiles to something harmless.
# ---------------------------------------------------------------------------

func _p(b) -> Dictionary:
	if b is Dictionary:
		var v = b.get("params")
		if v is Dictionary:
			return v
	return {}

func _num(d: Dictionary, key: String, fallback: float) -> float:
	var x = d.get(key)
	if x is float or x is int:
		return float(x)
	if x is String and str(x).is_valid_float():
		return float(x)
	return fallback

func _str(d: Dictionary, key: String, fallback: String) -> String:
	var v = d.get(key)
	if v == null:
		return fallback
	var s := str(v)
	return s if not s.is_empty() else fallback

func _bool(d: Dictionary, key: String, fallback: bool) -> bool:
	var v = d.get(key)
	if v == null:
		return fallback
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	if v is String:
		return str(v).to_lower() in ["true", "1", "yes"]
	return fallback

## A slider value, clamped to its documented range. `def` is the param's
## default; returning exactly `def` means the user never touched it.
func _slider(v: float, def: float, lo: float, hi: float) -> float:
	return clampf(v, lo, hi)

func _is_3d(ctx, root: Node) -> bool:
	if ctx != null and ctx is Dictionary:
		var v = ctx.get("is_3d")
		if v is bool:
			return v
	if root != null and is_instance_valid(root):
		return root is Node3D
	return true
