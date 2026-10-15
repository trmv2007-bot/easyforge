extends Node
## Features — the single wiring point for every optional brick feature.
##
## Registered as the autoload singleton "Features" (project.godot). On _ready it
## loads each feature module and lets it register itself into FeatureRegistry.
##
## WHY: this file is the ONLY place a feature is named. Each feature lives in
## its own file under src/features/ and calls Features.registry().register(...)
## for the brick kinds it implements. Ten builders can add ten features with
## zero edits to compiler.gd and zero overlap with each other — they only ever
## touch their own file plus (once, at setup) this list.
##
## To add a feature module:
##   1. create src/features/<name>.gd with a `func register(reg) -> void`
##   2. add its path to _MODULES below
## That's it. No other file changes.

var _registry: Node = null

func _ready() -> void:
	_registry = load("res://src/compiler/feature_registry.gd").new()
	add_child(_registry)
	for path in _MODULES:
		var res := load(path)
		if res == null:
			push_warning("[Features] failed to load module: " + path)
			continue
		var mod = res.new()
		if mod == null:
			push_warning("[Features] failed to instantiate module: " + path)
			continue
		if mod.has_method("register"):
			mod.register(_registry)
		else:
			push_warning("[Features] module has no register(): " + path)

func registry() -> Node:
	return _registry

# Modules are loaded in order; a later module may override an earlier kind.
# Keep the list alphabetical so parallel additions don't conflict.
const _MODULES: Array[String] = [
	"res://src/features/audio.gd",
	"res://src/features/bind.gd",
	"res://src/features/blueprint.gd",
	"res://src/features/collision.gd",
	"res://src/features/errors.gd",
	"res://src/features/gamepad.gd",
	"res://src/features/hierarchy.gd",
	"res://src/features/inputmap.gd",
	"res://src/features/light.gd",
	"res://src/features/look.gd",
	"res://src/features/menu.gd",
	"res://src/features/pathfind.gd",
	"res://src/features/perceive.gd",
	"res://src/features/rigid.gd",
	"res://src/features/saveload.gd",
	"res://src/features/states.gd",
	"res://src/features/theme.gd",
	"res://src/features/trigger.gd",
	"res://src/features/watch.gd",
	"res://src/features/widgets.gd",
	"res://src/features/undo.gd",
]
