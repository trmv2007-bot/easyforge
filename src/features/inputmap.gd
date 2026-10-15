extends Node
## inputmap — Wave 8: register the player's chosen keys as REAL Godot input
## actions, so gamepad / touch / rebinding become cheap instead of impossible.
##
## Before this, the generated movement script baked raw KEY_* ints as constants,
## so a gamepad or a touch control could never drive the player without editing
## generated code. This module registers five named actions (move_left,
## move_right, move_up, move_down, jump) in the project InputMap, bound to the
## keys the user picked in the Spawn brick, then attaches a tiny script that
## reads them via Input.is_action_pressed().
##
## The actions are registered with project settings + InputMap.add_action at
## build time, so the exported game carries them and any later brick (gamepad,
## touch) can add a second binding to the same action with one call.

# The canonical action names. Kept as constants so a later module (touch,
# gamepad) can add bindings to the SAME names instead of inventing its own.
const A_LEFT := "ef_move_left"
const A_RIGHT := "ef_move_right"
const A_UP := "ef_move_up"
const A_DOWN := "ef_move_down"
const A_JUMP := "ef_jump"

func register(reg) -> void:
	# Not a user-facing brick: it augments the Move brick's generated code, so it
	# registers no kind of its own. It is listed in features.gd so the module is
	# loaded and its helpers are available to the compiler, and deliberately
	# registers NOTHING so no phantom brick can appear in the palette.
	pass

func _noop(_b: Dictionary, _root: Node, _ctx) -> void:
	pass

## Register one named action bound to a single key. Idempotent: re-registering
## the same action replaces its bindings, so a rebuild cannot stack duplicates.
static func register_action(action: String, key_name: String) -> void:
	if action.is_empty() or key_name.is_empty():
		return
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)
	var kc: int = FeatureCtx.keycode(key_name)
	if kc == KEY_NONE:
		return
	var ev := InputEventKey.new()
	ev.physical_keycode = kc
	InputMap.action_add_event(action, ev)

## Register the five movement actions from the player's chosen controls.
## Called by the compiler when a Move brick is compiled.
static func register_controls(controls: Dictionary) -> void:
	register_action(A_LEFT, str(controls.get("key_left", "A")))
	register_action(A_RIGHT, str(controls.get("key_right", "D")))
	register_action(A_JUMP, str(controls.get("key_jump", "Space")))
	register_action(A_UP, str(controls.get("key_up", "W")))
	register_action(A_DOWN, str(controls.get("key_down", "S")))

## Add a SECOND binding (e.g. a gamepad button or a touch zone) to an action
## that already exists, without touching the keyboard binding. Returns false if
## the action was never registered, so callers can tell that movement is absent.
static func add_binding(action: String, ev: InputEvent) -> bool:
	if not InputMap.has_action(action) or ev == null:
		return false
	InputMap.action_add_event(action, ev)
	return true

## True when the named action exists and is currently held.
static func pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)
