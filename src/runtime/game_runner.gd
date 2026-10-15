extends Node
## GameRunner — in-app Play.
## Instantiates the compiled game scene and shows it in a dedicated SubViewport
## in the main window ("hit Play inside the app, no separate window").

signal game_stopped

var _current_root: Node = null
var _viewport: SubViewport = null
var _compiler = null

func _init():
	pass

func setup(compiler) -> void:
	_compiler = compiler

## Internal cleanup — removes any mounted game WITHOUT emitting game_stopped.
## Used by play() before mounting a fresh scene so it doesn't re-trigger the
## UI's stop handler mid-toggle (that was the "stop doesn't stop" bug).
func _teardown() -> void:
	if _current_root and is_instance_valid(_current_root):
		_current_root.queue_free()
	_current_root = null
	if _viewport and is_instance_valid(_viewport):
		for child in _viewport.get_children():
			child.queue_free()

## Compile the graph and mount it into the given SubViewport.
func play(graph, viewport: SubViewport) -> bool:
	_teardown()   # internal cleanup, no signal
	if _compiler == null:
		push_error("GameRunner: compiler not set")
		return false
	_viewport = viewport
	_viewport.gui_disable_input = false
	_viewport.handle_input_locally = true
	var scene = _compiler.compile_graph(graph)
	if scene == null:
		return false
	_viewport.add_child(scene)
	_current_root = scene
	return true

## User-facing stop — unmounts and notifies the UI.
func stop() -> void:
	_teardown()
	game_stopped.emit()

func is_playing() -> bool:
	return _current_root != null and is_instance_valid(_current_root)
