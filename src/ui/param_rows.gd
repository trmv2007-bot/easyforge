extends RefCounted
## ParamRows — the one place a brick's settings become real controls.
##
## The canvas node's fold-out and the inspector both need the same thing: one
## labelled row per schema key with a control that writes the value back. That
## used to be two near-identical 40-line copies, so an improvement landed in one
## and the other stayed broken (the inspector had no tooltips, the canvas had no
## sections). One builder, two callers.
##
## `setter` is the caller's Callable(value) — main.gd routes it through
## _set_param so a tweak is autosaved and undoable. This file never touches the
## graph or the undo stack; it only draws controls and reports what happened.

class_name ParamRows

## Build one section's rows into `parent`.
## opts: label_w (float), dense (bool), show_help (bool), font (int px)
static func build(parent: Control, kind: String, schema: Dictionary, params: Dictionary,
		setter: Callable, opts: Dictionary = {}) -> void:
	var label_w: float = float(opts.get("label_w", 96.0))
	var dense: bool = bool(opts.get("dense", false))
	var show_help: bool = bool(opts.get("show_help", false))
	var font_px: int = int(opts.get("font", 12))
	for key in schema:
		var spec: Dictionary = schema[key]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(row)

		var lbl := Label.new()
		lbl.text = str(spec.get("label", str(key).capitalize()))
		lbl.custom_minimum_size = Vector2(label_w, 0)
		lbl.add_theme_font_size_override("font_size", font_px)
		lbl.modulate = UiTheme.C_MUTED
		row.add_child(lbl)

		var help := BrickDocs.param_help(kind, str(key))
		var cur = params.get(key, spec.get("default"))
		var control := _make_control(kind, str(key), spec, cur, setter, font_px)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
		# The explanation goes on the label and the control, because a tooltip on
		# the box you are about to type into is the one you never hover.
		if not help.is_empty():
			lbl.tooltip_text = help
			control.tooltip_text = help

		# In the inspector the help is plain text on its own line: reading it
		# should not require knowing that a tooltip exists.
		if show_help and not help.is_empty():
			var hint := Label.new()
			hint.text = help
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_font_size_override("font_size", maxi(font_px - 2, 10))
			hint.modulate = UiTheme.C_MUTED
			parent.add_child(hint)
		if not dense:
			parent.add_child(_spacer(4))

static func _spacer(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, px)
	return c

## The right control for the schema type: a spinner for numbers, a dropdown for
## choices, a checkbox for bools, a text box otherwise. Unknown types land on the
## text box rather than printing an error — a new schema type must never blank
## the inspector.
static func _make_control(kind: String, key: String, spec: Dictionary, cur,
		setter: Callable, font_px: int) -> Control:
	var stype := str(spec.get("type", "text"))
	match stype:
		"number":
			var spin := SpinBox.new()
			spin.min_value = float(spec.get("min", 0.0))
			spin.max_value = float(spec.get("max", 100.0))
			spin.step = float(spec.get("step", 1.0))
			spin.value = float(cur) if cur != null else float(spec.get("default", 0.0))
			spin.custom_minimum_size = Vector2(120, 0)
			spin.add_theme_font_size_override("font_size", font_px)
			spin.value_changed.connect(func(v): setter.call(key, v))
			return spin
		"choice":
			var opt := OptionButton.new()
			var options: Array = options_for(kind, key, spec)
			var sel := 0
			for i in options.size():
				opt.add_item(option_label(options[i]), i)
				if str(options[i]) == str(cur):
					sel = i
			if options.is_empty():
				opt.add_item("-", 0)
			opt.selected = clampi(sel, 0, maxi(options.size() - 1, 0))
			opt.add_theme_font_size_override("font_size", font_px)
			opt.item_selected.connect(func(idx):
				if idx < options.size():
					setter.call(key, str(options[idx]))
			)
			return opt
		"bool":
			var chk := CheckBox.new()
			chk.button_pressed = bool(cur) if cur != null else bool(spec.get("default", false))
			chk.add_theme_font_size_override("font_size", font_px)
			# the box alone is a tiny target; clicking the row's label toggles it too
			chk.toggled.connect(func(v): setter.call(key, v))
			return chk
		_:
			var le := LineEdit.new()
			le.text = str(cur) if cur != null else str(spec.get("default", ""))
			le.add_theme_font_size_override("font_size", font_px)
			le.text_changed.connect(func(t): setter.call(key, t))
			return le

## Choice options for a param. The spawn "model" is the one place the built-in
## art library talks to the UI directly: the compiler already accepts any named
## look from Assets (unknown names fall back to a primitive), so the dropdown
## offers the whole library instead of the schema's four guesses.
static func options_for(kind: String, key: String, spec: Dictionary) -> Array:
	if kind == "spawn" and key == "model":
		var assets := _assets_singleton()
		if assets != null and assets.has_method("model_choices"):
			var named = assets.model_choices()
			if named is Array and not named.is_empty():
				return named
	return spec.get("options", [])

## The Assets autoload, resolved through the tree rather than by name: a static
## helper has no `self` to walk up from, and the autoload identifier is not
## always resolvable at parse time (that is what silently disabled the feature
## registry once). No Assets, no crash — the schema's own options are used.
static func _assets_singleton() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/Assets")
	return null

## A user-facing label for an option value: "mushroom_red" reads as
## "Mushroom Red", not "Mushroom_red".
static func option_label(value) -> String:
	return str(value).replace("_", " ").capitalize()

## Group a brick kind's schema keys into labelled sections, in the order a
## person should read them. Keys we have not placed fall into "More settings"
## at the end, so an unpicked-up schema key is never invisible.
static func sections_for(kind: String, schema: Dictionary) -> Dictionary:
	var sections := {}
	match kind:
		"spawn":
			sections["What it is"] = ["model", "position_y"]
			sections["Controls"] = ["key_left", "key_right", "key_up", "key_down", "key_jump"]
			sections["Jump feel"] = ["coyote_time", "jump_buffer", "jump_cut", "fall_gravity"]
		"move":
			sections["Movement"] = ["style", "speed", "jump", "gravity"]
		"camera":
			sections["Camera"] = ["mode", "distance", "height", "smooth"]
		"collide":
			sections["Collision"] = ["with", "action"]
		"score":
			sections["Scoring"] = ["variable", "op", "amount"]
		"winlose":
			sections["Win / Lose"] = ["condition", "value"]
		"health":
			sections["Health"] = ["max", "damage"]
		"variable":
			sections["Variable"] = ["name", "scope", "type"]
			sections["On Event"] = ["op", "amount", "value"]
		"rule":
			sections["Condition"] = ["cond_source", "cond_var", "cond_op", "cond_value", "cond_key"]
			sections["Then Do"] = ["actions"]
		"platform":
			sections["Surface"] = ["preset", "one_way", "bounce", "friction"]
			sections["Size"] = ["width", "height"]
		"background":
			sections["Background"] = ["layers", "theme"]
		"sky":
			sections["Sky"] = ["preset"]
		"door":
			sections["Door"] = ["target_level", "target_entry", "transition", "needs_var"]
		"entry":
			sections["Entry Point"] = ["marker"]
		"inventory":
			sections["Inventory"] = ["item", "op", "amount", "need"]
		"level":
			sections["Level"] = ["pattern", "tile", "theme"]
		"timer":
			sections["Timer"] = ["name", "seconds", "mode", "every", "on_end"]
		"trigger":
			sections["Zone"] = ["shape", "size", "visible_hint"]
			sections["Trigger"] = ["target", "once", "needs_var"]
			sections["Actions"] = ["on_enter", "on_exit"]
		"collider":
			sections["Collision"] = ["layer", "collides_with", "solid"]
			sections["Shape"] = ["shape", "size", "position_y"]
		"save":
			sections["Saving"] = ["mode", "slot", "key"]
			sections["What to save"] = ["include_position", "include_vars", "include_score"]
		"checkpoint_save":
			sections["Save Point"] = ["slot", "size", "once"]
		"look":
			sections["Preset"] = ["preset"]
			sections["Grade"] = ["bloom", "saturation", "contrast", "brightness"]
			sections["Effects"] = ["vignette", "ssao", "fog", "apply_2d"]
		"gamepad":
			sections["Gamepad"] = ["enabled", "device", "deadzone", "invert_y"]
			sections["Vibration"] = ["vibrate", "vibrate_strength"]
		"screen":
			sections["Screen"] = ["kind_of_screen", "title", "subtitle"]
			sections["Behavior"] = ["background", "transition", "show_on_start", "pause_game"]
		"button":
			sections["Button"] = ["label", "action", "parent_screen"]
			sections["Target"] = ["target_screen", "var_name", "var_value"]
		"undo":
			sections["Undo"] = ["key", "depth", "track_position", "track_vars"]
		"pathfind":
			sections["Behavior"] = ["mode", "target", "speed", "arrive_radius"]
			sections["Advanced"] = ["repath", "guard_radius", "avoid", "draw_path", "points"]
		"state":
			sections["States"] = ["var_name", "initial", "states"]
			sections["Rules"] = ["transitions", "owner", "show_state"]
		"widget":
			sections["Control"] = ["widget_kind", "label", "width", "position"]
			sections["When used"] = ["action", "var_name", "var_value"]
			sections["Range & choices"] = ["min_value", "max_value", "step", "options"]
		"watch":
			sections["Watch"] = ["var_names", "position", "font_size"]
			sections["Behavior"] = ["editable", "show_changes"]
		"error_panel":
			sections["Problem Reporter"] = ["show_on_start", "auto_open", "detail_level"]
		"light":
			sections["Light"] = ["kind_of_light", "color_name", "intensity", "range"]
			sections["Shadows & flicker"] = ["shadows", "shadow_softness", "flicker", "flicker_speed"]
		"occluder":
			sections["Occluder"] = ["shape", "width", "height"]
		"blueprint_def":
			sections["Blueprint"] = ["name", "description"]
		"blueprint":
			sections["Place"] = ["blueprint_name", "count"]
			sections["Arrange"] = ["layout", "spread", "rows", "overrides"]
		"attach":
			sections["Attach"] = ["child_brick", "parent_brick"]
			sections["Behavior"] = ["inherit_rotation", "follow_position", "visible"]
		"rigid":
			sections["Object"] = ["model", "size", "color_name", "start_asleep"]
			sections["Physics"] = ["mass", "gravity_scale", "bounciness", "friction"]
			sections["Advanced"] = ["linear_damping", "angular_damping", "freeze"]
		"audio":
			sections["Sound"] = ["sound_kind", "bus", "volume_db"]
			sections["Playback"] = ["play_on_start", "loop"]
		"perceive":
			sections["Senses"] = ["sight_range", "sight_angle", "hearing_range", "needs_line_of_sight"]
			sections["When it sees you"] = ["on_notice", "alert_var", "event_name", "memory_seconds"]
			sections["Debug"] = ["show_cone"]
		"style":
			sections["Look"] = ["preset", "accent", "font_size", "corner_radius"]
			sections["Screen changes"] = ["transition", "transition_seconds"]
		"hud":
			sections["What to show"] = ["widget", "var_name", "label"]
			sections["Scale & place"] = ["max_var", "max_value", "show_percent", "position", "color_name"]
		"sound":
			sections["Sound"] = ["kind", "volume"]
		"particles":
			sections["Particles"] = ["effect", "amount", "color"]
		"animation":
			sections["Animation"] = ["motion", "speed"]
		"moving_platform":
			sections["Platform"] = ["distance", "speed", "axis"]
		"enemy_patrol":
			sections["Enemy"] = ["distance", "speed"]
		"hazard":
			sections["Hazard"] = ["damage"]
		"follow":
			sections["Follow"] = ["target", "speed"]
		"destroy":
			sections["Destroy"] = ["on"]
	# NOTE: there used to be a second "timer" arm here (a leftover from the first
	# version of the brick). GDScript takes the first match, so it was dead code
	# pretending to be a second definition — one arm, the full key list, now.
	if sections.is_empty():
		# catch-all: every schema key under one section
		return {"Settings": schema.keys()}
	# Keep only keys that exist in the schema, in the order written above, and
	# collect what we did not place so nothing becomes invisible.
	var placed := {}
	var trimmed := {}
	for section_name in sections:
		var kept: Array = []
		for key in (sections[section_name] as Array):
			if schema.has(key) and not placed.has(key):
				kept.append(key)
				placed[key] = true
		if not kept.is_empty():
			trimmed[section_name] = kept
	var leftovers: Array = []
	for key in schema:
		if not placed.has(key):
			leftovers.append(key)
	# a key nobody grouped is shown under an honest header instead of vanishing
	if not leftovers.is_empty():
		trimmed["More settings"] = leftovers
	return trimmed
