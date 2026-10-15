extends Node
## FeatureRegistry — the decoupling layer that lets many builders extend the
## compiler WITHOUT editing compiler.gd.
##
## Why this exists: the compiler's pass-1/pass-2 match statements used to be the
## single bottleneck every new brick had to touch. Ten parallel builders editing
## one match block = merge collisions. Instead, each feature module registers a
## builder for its brick kinds here, and compiler.gd makes exactly ONE call per
## brick. Adding a feature = writing a new file + one register() call in it.
##
## Contract for a builder Callable:
##   func(brick: Dictionary, root: Node, ctx: Dictionary) -> void
## `ctx` carries the compile context (compiler ref, entities map, player node,
## is_3d flag) so a builder can reuse the core helpers without owning them.
##
## Registration is idempotent: re-registering the same kind overwrites, so
## reloading a module (tests, hot-reload) is safe.

const LOG_PREFIX := "[FeatureRegistry] "

# kind -> Callable(brick, root, ctx)
var _builders := {}
# kinds that must be seeded on GameState BEFORE the resets would wipe them
var _seeders := {}
# kinds the pass-1 loop should hand to us (event/scene-level bricks)
var _pass1_kinds := {}

func register(kind: String, fn: Callable) -> void:
	if kind.strip_edges().is_empty() or not fn.is_valid():
		push_error(LOG_PREFIX + "cannot register invalid builder for '%s'" % kind)
		return
	_builders[kind] = fn

## Bricks that need a GameState seed (like Variable/Inventory do). The seeder
## runs after the resets so its values survive.
func register_seeder(kind: String, fn: Callable) -> void:
	if kind.strip_edges().is_empty() or not fn.is_valid():
		push_error(LOG_PREFIX + "cannot register invalid seeder for '%s'" % kind)
		return
	_seeders[kind] = fn

## Declare a kind that must be built in pass 1 (before entities exist) rather
## than pass 2. Most bricks belong in pass 2; event/setup bricks use this.
func register_pass1(kind: String) -> void:
	_pass1_kinds[kind] = true

func has(kind: String) -> bool:
	return _builders.has(kind)

func is_pass1(kind: String) -> bool:
	return _pass1_kinds.has(kind)

func kinds() -> Array:
	return _builders.keys()

## Run the registered builder for `kind`. Returns true when one ran (so the
## caller knows the brick was handled and should not fall back to a placeholder).
func build(kind: String, brick: Dictionary, root: Node, ctx: Dictionary) -> bool:
	if not _builders.has(kind):
		return false
	var fn: Callable = _builders[kind]
	if not fn.is_valid():
		push_warning(LOG_PREFIX + "builder for '%s' went invalid; skipping" % kind)
		return false
	fn.call(brick, root, ctx)
	return true

## Run a registered seeder against a state object. Returns true when one ran.
func seed(kind: String, brick: Dictionary, state, ctx: Dictionary) -> bool:
	if not _seeders.has(kind):
		return false
	var fn: Callable = _seeders[kind]
	if not fn.is_valid():
		return false
	fn.call(brick, state, ctx)
	return true

func clear() -> void:
	_builders.clear()
	_seeders.clear()
	_pass1_kinds.clear()
