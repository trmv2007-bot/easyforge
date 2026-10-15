extends Node
## audio — one "audio" brick = one routed, procedurally synthesised sound.
##
## WHY IT MATTERS: until now every sound in a compiled game plays through a
## single flat player at one volume, so a player cannot turn music down
## without muting effects. This brick routes each sound onto a NAMED Godot
## AudioBus (Music / SFX / UI / Ambient), which is exactly what a mixer is:
## separate faders. The bus is created once, reused by every later brick, and
## its volume is set in dB.
##
## NO ASSET FILES (contract rule 1). Every waveform is generated in code as
## PCM bytes into an AudioStreamWAV — a coin is two quick sine tones, a jump
## is a rising sweep, a hit is a deterministic noise burst, a win is a
## three-note arpeggio. Nothing is loaded from disk.
##
## NODES CREATED (per audio brick)
##   2D -> AudioStreamPlayer2D   "Audio_<id>"   group "audio_<bus>"
##   3D -> AudioStreamPlayer3D   "Audio_<id>"   group "audio_<bus>"
##         (positioned from the brick's `position` param; 2D uses Node2D
##          attenuation, 3D uses unit_size/max_distance so it falls off
##          with distance like a real world sound)
##
## ---------------------------------------------------------------------------
## API FACTS VERIFIED against the real Godot 4.7.2 engine with live probes
## (property-list dumps + a run that actually built buses, streams and
## players). NONE of these were guessed:
##   - `AudioServer.add_bus(at_position := -1)` returns VOID, not an index.
##     The new bus's index is `AudioServer.bus_count - 1` after the call.
##     (The probe proved: add_bus() with a bogus at_position=99 did NOT
##     append — it silently did nothing useful — so always call it with no
##     argument and read bus_count.)
##   - `AudioServer.get_bus_index("Name")` returns -1 for an unknown name.
##   - `AudioServer.set_bus_name(idx, "Name")` renames; the name is then
##     found by get_bus_index again.
##   - `AudioServer.set_bus_volume_db(idx, db)` / `get_bus_volume_db(idx)`
##     exist and round-trip exactly. The engine does NOT clamp the value it
##     stores (probe: setting 999.0 read back 999.0), so THIS module clamps
##     to -60..6 before calling it, as the param contract requires.
##   - Reading `get_bus_volume_db(idx)` with an out-of-range index raises a
##     runtime error, so every read is guarded by bus_count.
##   - AudioStreamWAV properties: `data` (PackedByteArray), `format` (int),
##   `mix_rate` (int), `stereo` (bool), `loop_mode` (int). Constants:
##     FORMAT_8_BITS = 0, FORMAT_16_BITS = 1, LOOP_DISABLED = 0,
##     LOOP_FORWARD = 1.
##   - 16-bit PCM in `data` is INTERLEAVED LITTLE-ENDIAN SIGNED when
##     stereo=false: 2 bytes per frame, low byte first (verified: a
##     non-negative sine's first bytes were 0,0,14,19 — i.e. small
##     positive little-endian values).
##   - 8-bit PCM is UNSIGNED with 128 as the centre (matching the existing
##     GameState synthesizer).
##   - `AudioStreamWAV.loop_mode` is the looping switch. There is NO
##     `loop` bool on the stream (probe: loop_mode default 0, set to
##     LOOP_FORWARD and get_length() was unchanged). `AudioStreamPlayer`
##     has NO loop property either — looping lives on the stream alone.
##   - `AudioStreamPlayer2D` is a Node2D and `AudioStreamPlayer3D` is a
##     Node3D, but they are SIBLINGS: both extend Node directly (verified
##     with ClassDB.get_parent_class), so they share NO common base that
##     carries `bus`/`stream`/`play()`. Properties are set per class.
##   - A script that `extends AudioStreamPlayer` CANNOT be attached to an
##     AudioStreamPlayer2D/3D node — the engine refuses it outright
##     ("Script inherits from native type 'AudioStreamPlayer', so it can't
##     be assigned to an object of type 'AudioStreamPlayer2D'"). So the
##     generated _ready script does NOT extend the player class; the brick
##     node itself is a plain Node and the players are children. See
##     STRUCTURE below.
##   - Assigning `player.bus = "a name that does not exist"` does NOT
##     error: the engine silently falls back to Master (probe: read back
##     "Master"). That is still wrong for us, so this module creates the
##     bus BEFORE assigning it and only ever assigns a verified name.
##   - `AudioStreamPlayer.play()` / `stop()` / `is_playing()` exist on all
##     three player classes.
##
## STRUCTURE (why the brick node is not the player itself): a generated
## script must be attachable to the node, and a script extending
## AudioStreamPlayer cannot attach to a 2D/3D player. So:
##     Audio_<id>  (Node)                 <- the entity published in
##       |                                     ctx.entities, carries the
##       `--> Player (AudioStreamPlayer2D|3D)   generated _ready script
##                                                  that handles
##                                                  play_on_start
## The player itself is the first child of the entity node and is what
## groups are queried for, so a later brick does
## `get_tree().get_first_node_in_group("audio_sfx")` and finds a real
## player with a real stream.
##
## INTEGRATOR PARAMS (this module only READS them; the integrator adds them
## to brick.gd's PARAM_SCHEMA + KIND):
##   bus           choice [master, music, sfx, ui, ambient]  default "sfx"
##   volume_db     number -60.0..6.0 step 1.0              default 0.0
##   sound_kind    choice [coin, jump, hit, hurt, win, lose, click, pickup,
##                          powerup, blast, select, theme]
##                                                          default "coin"
##   loop          bool                                    default false
##   play_on_start bool                                    default true
##   position      array of 2|3 numbers                    optional
##   KIND entry:  "audio": {"label": "Audio", "icon": "🔊",
##                          "in": [FLOW], "out": []}

# FeatureCtx's class_name is not in scope in a feature module without an
# explicit preload — the established pattern (see src/features/trigger.gd).
const FeatureCtx = preload("res://src/compiler/feature_ctx.gd")

const KIND := "audio"

# The buses this brick may route to. "master" maps to Godot's built-in
# Master bus (index 0, already present); the other four are created on
# demand and reused. Verified: get_bus_index("Master") == 0 in a fresh
# engine, and every other bus must be added by us.
const BUSES := ["master", "music", "sfx", "ui", "ambient"]
const BUS_MASTER := "master"
# Godot capitalises the four built-in names; ours are lower-case so a bus
# we add reads consistently with the ones the user picked. Godot's own
# default bus is "Master" — keep that exact spelling when reusing it.
const GODOT_MASTER_NAME := "Master"
# A bus the does not exist and cannot be created falls back to this.
const FALLBACK_BUS := BUS_MASTER

const DEF_BUS := "sfx"
const DEF_KIND := "coin"

# The param contract's hard dB range. The engine stores whatever it is
# given (probe: 999.0 read back as 999.0), so clamping is OUR job.
const VOL_MIN := -60.0
const VOL_MAX := 6.0
const DEF_VOL := 0.0

const SOUND_KINDS := ["coin", "jump", "hit", "hurt", "win", "lose", "click", "pickup", "powerup", "blast", "select", "theme"]

## Kinds that are music, not effects: they are longer than the SFX contract
## cap, always loop, and belong behind the music fader.
const MUSIC_KINDS := ["theme"]
const MUSIC_SECONDS := 4.0          # one seamless 4-second loop

# Synthesis constants. 22050 Hz is a quarter of CD rate: plenty for these
# short blips (the highest tone is ~1.8 kHz, comfortably below the 11 kHz
# Nyquist limit) and it keeps every buffer tiny. 16-bit is the format the
# engine decodes with the least fuss and gives us full-range dynamics.
const MIX_RATE := 22050
# Contract requirement: "keep each under ~0.4s".
const MAX_SECONDS := 0.4
const MAX_FRAMES := int(float(MIX_RATE) * MAX_SECONDS)
# Peak amplitude in the 16-bit domain. 0.8 of full scale leaves headroom so
# several sounds overlapping never clip.
const PEAK16 := 0.8

# Spatial falloff. 3D: unit_size is the distance at which the sound has
# dropped 6 dB and max_distance is where it stops; 2D: max_distance +
# attenuation do the same job on a flat world.
const UNIT_SIZE := 12.0
const MAX_DISTANCE := 90.0
const ATTENUATION := 1.6

# The module-level cache. A graph with ten "coin" bricks must not
# synthesise ten identical PCM buffers, and AudioServer.bus_count must not
# grow because two bricks ask for the SFX bus. `static` works in this
# engine (verified) and is a plain Dictionary keyed by name.
static var _bus_ready := {}    # bus name -> true
static var _stream_cache := {} # sound kind -> AudioStreamWAV

func register(reg) -> void:
	if reg == null or not reg.has_method("register"):
		push_error("[audio] no feature registry available")
		return
	reg.register(KIND, _build)

# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------

## One "audio" brick -> one routed player with a synthesised stream.
func _build(b: Dictionary, root: Node, ctx) -> void:
	if root == null or not is_instance_valid(root):
		return
	if not (b is Dictionary):
		return

	var p := FeatureCtx.params(b)
	var bid := FeatureCtx.bid(b)

	# The compiler offers every brick to the registry in BOTH pass 1 and
	# pass 2 (verified with a live probe: a single audio brick produced two
	# player trees, the pass-1 one with a stale stream). Build once per
	# brick id and no-op on the second visit, otherwise every audio brick
	# plays twice and the group counts double.
	if _already_built(root, bid):
		return

	# The bus param is read as a plain string, NOT through _choice(): a name
	# that is not one of the five known buses must reach _ensure_bus so it
	# can fall back to Master. Validating it here would silently re-route a
	# typo to SFX, which is a wrong answer that looks right.
	var bus_name := _str(p, "bus", DEF_BUS).strip_edges().to_lower()
	var kind := _choice(p, "sound_kind", SOUND_KINDS, DEF_KIND)
	var vol := _clamp(_num(p, "volume_db", DEF_VOL), VOL_MIN, VOL_MAX, DEF_VOL)
	var loop := FeatureCtx.bbool(b, "loop", false)
	var play_on_start := FeatureCtx.bbool(b, "play_on_start", true)
	# Music always loops, and a theme left on the default SFX fader would let a
	# player mute their soundtrack while the coin pings kept playing — so an
	# un-customised music brick routes itself to the music bus.
	if kind in MUSIC_KINDS:
		loop = true
		if bus_name == DEF_BUS:
			bus_name = "music"

	var is3 := _is_3d(ctx, root)

	# 1. the bus, created once and reused by every later audio brick
	var resolved := _ensure_bus(bus_name)

	# 2. the PCM stream, cached per kind (identical sounds share a buffer)
	var stream := _stream_for(kind, loop)
	if stream == null:
		push_warning("[audio] could not synthesise '%s' for '%s'" % [kind, bid])
		return

	# 3. the entity node: a plain Node, so a generated script can attach.
	#    (A script extending AudioStreamPlayer cannot attach to a 2D/3D
	#    player — the engine refuses it. See the header's STRUCTURE note.)
	var entity := Node.new()
	entity.name = "Audio_%s" % bid if not bid.is_empty() else "Audio"

	var player: Node = _make_player(is3, entity.name + "_Player")
	if player == null:
		return
	player.stream = stream
	# Only ever assign a bus name that exists — the engine silently falls
	# back to Master on an unknown name, which would be a silent routing bug.
	player.bus = resolved
	player.volume_db = vol
	# looping lives on the STREAM, not the player (there is no loop property
	# on AudioStreamPlayer — verified)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	# autoplay would fire the moment the node enters the tree, before the
	# caller could ever stop it. play_on_start is handled by the generated
	# _ready instead, which is where "false" can actually mean silent.
	player.autoplay = false

	if is3:
		var p3 := player as AudioStreamPlayer3D
		if p3 != null:
			p3.unit_size = UNIT_SIZE
			p3.max_distance = MAX_DISTANCE
			p3.position = _vec3_of(p.get("position", null), Vector3(0.0, 1.5, 0.0))
	else:
		var p2 := player as AudioStreamPlayer2D
		if p2 != null:
			p2.max_distance = MAX_DISTANCE
			p2.attenuation = ATTENUATION
			p2.position = _vec2_of(p.get("position", null), Vector2(500.0, 250.0))

	# findable by a later brick: a group named by the bus, e.g. "audio_sfx"
	player.add_to_group(_group_for(resolved))
	entity.add_child(player)

	root.add_child(entity)

	# play_on_start is a runtime decision, so it is generated code, not a
	# property: the script only calls play() when the param says to.
	var src := _ready_source(play_on_start)
	if FeatureCtx.attach_script(entity, src) != OK:
		push_error("[audio] play_on_start script failed to compile for '%s'" % entity.name)

	var ents = _ctxv(ctx, "entities", null)
	if ents is Dictionary and not bid.is_empty():
		ents[bid] = entity

# ---------------------------------------------------------------------------
# Idempotence — the compiler calls a builder in pass 1 AND pass 2
# ---------------------------------------------------------------------------

## Has this brick already been built into `root`? Matched by walking the
## root's children for an Audio_* entity whose brick id matches. Node names
## are NOT reliable (Godot auto-renames duplicate siblings to @Class@N), so
## the check reads the name prefix and the id suffix rather than an exact
## name match, and an empty id always builds (a graph with no ids cannot be
## de-duplicated, and building one player is better than none).
func _already_built(root: Node, bid: String) -> bool:
	if bid.is_empty():
		return false
	var want := "Audio_%s" % bid
	for ch in root.get_children():
		if str(ch.name) == want:
			# found the entity from the earlier pass; confirm it really has
			# a player child so a half-built tree is not treated as done
			for g in ch.get_children():
				if g is AudioStreamPlayer or g is AudioStreamPlayer2D or g is AudioStreamPlayer3D:
					return true
	return false

# ---------------------------------------------------------------------------
# Bus management — created ONCE per bus, reused forever after
# ---------------------------------------------------------------------------

## Resolve `bus_name` to a bus that definitely exists, creating it on the
## first request. Returns the name to assign to a player's `bus`.
## An UNKNOWN name falls back to Master rather than creating a bus for a
## typo — creating "Junk_bus" would add a dead fader to the mixer.
func _ensure_bus(bus_name: String) -> String:
	var raw := str(bus_name).strip_edges().to_lower()
	if raw.is_empty():
		return GODOT_MASTER_NAME
	if raw not in BUSES:
		push_warning("[audio] unknown bus '%s'; using Master" % raw)
		return GODOT_MASTER_NAME

	var name := _display_name(raw)
	if name.is_empty():
		return GODOT_MASTER_NAME

	# reuse: the bus is already in the engine's table
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0 and idx < AudioServer.bus_count:
		_bus_ready[raw] = true
		return name

	if raw == BUS_MASTER:
		# Master always exists in a Godot project, but if it somehow does
		# not, fall back rather than trying to create Godot's own bus.
		push_warning("[audio] Master bus missing; routing to index 0")
		return GODOT_MASTER_NAME

	# create it. add_bus() returns VOID and appends at the end, so the new
	# index is bus_count - 1 afterwards (verified against the engine).
	var before := AudioServer.bus_count
	AudioServer.add_bus()
	var new_idx := AudioServer.bus_count - 1
	if new_idx < before or new_idx >= AudioServer.bus_count:
		# add_bus refused (e.g. a bogus position): do not invent an index
		push_warning("[audio] could not create bus '%s'; using Master" % name)
		return GODOT_MASTER_NAME

	AudioServer.set_bus_name(new_idx, name)
	# confirm the rename actually took before anyone routes to it
	if AudioServer.get_bus_index(name) != new_idx:
		push_warning("[audio] bus rename to '%s' failed; using Master" % name)
		return GODOT_MASTER_NAME

	# this brick's volume_db applies to the bus it owns. Later bricks that
	# name the same bus reuse it; only the FIRST brick's volume is written,
	# which is what "one fader per bus" means for a no-code tool.
	var vol: float = _bus_default_volume(raw)
	AudioServer.set_bus_volume_db(new_idx, vol)
	_bus_ready[raw] = true
	return name

## The user's lower-case bus name as a bus label. "master" maps to Godot's
## own "Master"; the rest are capitalised so they read like real faders.
func _display_name(bus_name: String) -> String:
	var s := str(bus_name).strip_edges().to_lower()
	if s.is_empty():
		return GODOT_MASTER_NAME
	if s == BUS_MASTER:
		return GODOT_MASTER_NAME
	return s.capitalize()

## A sane starting fader per bus, so Music does not start at full blast
## over the SFX. Music sits a little down; SFX/UI are the reference.
func _bus_default_volume(bus_name: String) -> float:
	match str(bus_name).to_lower():
		"music": return -6.0
		"ambient": return -12.0
		_: return 0.0

## The group name a later brick queries to find players on this bus.
func _group_for(resolved_bus: String) -> String:
	var s := str(resolved_bus).strip_edges().to_lower()
	return "audio_%s" % s if not s.is_empty() else "audio_master"

# ---------------------------------------------------------------------------
# Player construction — the 2D/3D classes are siblings (both extend Node),
# so there is no shared base carrying stream/bus/play. One per class.
# ---------------------------------------------------------------------------

func _make_player(is3: bool, name: String) -> Node:
	if is3:
		var p := AudioStreamPlayer3D.new()
		p.name = name
		return p
	var q := AudioStreamPlayer2D.new()
	q.name = name
	return q

# ---------------------------------------------------------------------------
# PCM synthesis — the whole point of this module. NO ASSET FILES.
# Every buffer below is built from arithmetic and packed into
# AudioStreamWAV.data as 16-bit signed little-endian mono PCM.
# ---------------------------------------------------------------------------

## The cached (or freshly synthesised) stream for a sound kind.
func _stream_for(kind: String, loop: bool) -> AudioStreamWAV:
	var key := "%s_%s" % [kind, "loop" if loop else "once"]
	if _stream_cache.has(key):
		return _stream_cache[key]
	var w := _synth(kind, loop)
	if w != null:
		_stream_cache[key] = w
	return w

## Dispatch to the waveform for a sound kind. Each recipe is a list of
## (frequency, start_fraction, length_fraction, amplitude) segments; the
## noise kinds use the noise generator instead.
func _synth(kind: String, loop: bool) -> AudioStreamWAV:
	var k := str(kind).strip_edges().to_lower()
	match k:
		"coin":
			# two quick sine tones: the classic pickup, a fifth apart
			return _wav_from_recipe([
				[988.0, 0.00, 0.35, 0.55],   # B5
				[1319.0, 0.30, 0.50, 0.55],  # E6, overlapping the first
				[1760.0, 0.55, 0.45, 0.45],  # A6, the sparkle
			], 0.28)
		"pickup":
			# a softer, rounder coin: one warm tone that bends up slightly
			return _wav_from_recipe([
				[784.0, 0.00, 0.55, 0.50],
				[1046.0, 0.45, 0.55, 0.45],
			], 0.30)
		"jump":
			# a rising sweep: the frequency glides up over the whole blip
			return _wav_sweep(360.0, 920.0, 0.22, 0.60)
		"click":
			# UI tick: a very short high blip, as short as the contract allows
			return _wav_from_recipe([[1568.0, 0.00, 0.40, 0.40]], 0.05)
		"hit":
			# filtered noise burst: the thud of an impact
			return _wav_noise(0.20, 900.0, 0.75, 7)
		"hurt":
			# a lower, longer, buzzier noise — damage reads rougher than a hit
			return _wav_noise(0.32, 420.0, 0.85, 11)
		"win":
			# a three-note arpeggio, each note clearly separated
			return _wav_from_recipe([
				[784.0, 0.00, 0.30, 0.50],   # G5
				[988.0, 0.28, 0.30, 0.50],  # B5
				[1319.0, 0.56, 0.44, 0.55], # E6, held a touch longer
			], 0.38)
		"lose":
			# a falling pair of tones: defeat drops in pitch
			return _wav_from_recipe([
				[392.0, 0.00, 0.45, 0.50],   # G4
				[262.0, 0.40, 0.60, 0.55],  # C4, lower and longer
			], 0.38)
		"powerup":
			# a rising run of four notes — the classic "get stronger"
			return _wav_from_recipe([
				[523.0, 0.00, 0.25, 0.45],    # C5
				[659.0, 0.20, 0.25, 0.45],   # E5
				[784.0, 0.40, 0.25, 0.45],   # G5
				[1046.0, 0.60, 0.40, 0.50],  # C6, the landing
			], 0.38)
		"blast":
			# a low, rolled-off noise thump — explosions
			return _wav_noise(0.36, 260.0, 0.9, 23)
		"select":
			# a menu confirm: two soft close notes, blip then answer
			return _wav_from_recipe([
				[880.0, 0.00, 0.30, 0.35],
				[1175.0, 0.22, 0.40, 0.35],
			], 0.18)
		"theme":
			# the only kind longer than the SFX cap: a gentle looping tune
			return _wav_music()
		_:
			# unknown kind: a neutral short blip rather than silence, so a
			# junk param still produces audible feedback
			return _wav_from_recipe([[440.0, 0.00, 0.50, 0.45]], 0.15)

## A tone-based recipe: each segment is [freq, start_frac, len_frac, amp].
## Segments are additive, so overlapping notes sound together. Each segment
## carries its own short attack/release envelope, so a recipe with several
## notes reads as distinct strikes instead of one mush.
func _wav_from_recipe(segments: Array, total_seconds: float) -> AudioStreamWAV:
	var frames := _frames_for(total_seconds)
	if frames <= 0:
		return null
	var samples := PackedFloat32Array()
	samples.resize(frames)
	for seg in segments:
		if not (seg is Array) or seg.size() < 4:
			continue
		var freq: float = max(_f(seg[0]), 1.0)
		var start: float = clampf(_f(seg[1]), 0.0, 1.0)
		var len: float = clampf(_f(seg[2]), 0.01, 1.0)
		var amp: float = clampf(_f(seg[3]), 0.0, 1.0)
		var i0 := int(float(frames) * start)
		var i1 := int(float(frames) * (start + len))
		i0 = clampi(i0, 0, frames - 1)
		i1 = clampi(i1, i0 + 1, frames)
		var n := i1 - i0
		if n <= 0:
			continue
		# a plucked-strike envelope: 8% attack, the rest decaying
		var attack: int = max(int(float(n) * 0.08), 1)
		for i in n:
			var t := float(i) / float(n)
			var env: float = _envelope(i, n, attack)
			var v: float = sin(float(i0 + i) * freq * TAU / float(MIX_RATE)) * env * amp
			samples[i0 + i] += v
	return _wav_from_samples(samples)

## A linear frequency glide from `f0` to `f1` — the rising sweep a jump
## makes. The phase is integrated from the instantaneous frequency, so the
## glide is smooth rather than a stack of stepped tones.
func _wav_sweep(f0: float, f1: float, seconds: float, amp: float) -> AudioStreamWAV:
	var frames := _frames_for(seconds)
	if frames <= 0:
		return null
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var phase := 0.0
	var attack: int = max(int(float(frames) * 0.08), 1)
	for i in frames:
		var t := float(i) / float(frames)
		var freq: float = lerpf(max(_f(f0), 1.0), max(_f(f1), 1.0), t)
		phase += freq * TAU / float(MIX_RATE)
		var env: float = _envelope(i, frames, attack)
		samples[i] = sin(phase) * env * clampf(amp, 0.0, 1.0)
	return _wav_from_samples(samples)

## A noise burst shaped by a one-pole low-pass, then enveloped. This is
## what an impact sounds like: broadband noise with the top rolled off.
## The noise is a deterministic LCG, NOT randf() — the contract forbids
## randf() in positions/geometry and determinism matters here too, so the
## same brick always synthesises byte-identical audio.
func _wav_noise(seconds: float, cutoff_hz: float, amp: float, seed_int: int) -> AudioStreamWAV:
	var frames := _frames_for(seconds)
	if frames <= 0:
		return null
	# one-pole coefficient from the cutoff: a = 1 - exp(-2*pi*fc/fs)
	var fc: float = clampf(_f(cutoff_hz), 20.0, float(MIX_RATE) * 0.45)
	var a := 1.0 - exp(-TAU * fc / float(MIX_RATE))
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var lcg := int(seed_int) & 0x7FFFFFFF
	var lp := 0.0
	var attack: int = max(int(float(frames) * 0.02), 1)
	for i in frames:
		lcg = (lcg * 1103515245 + 12345) & 0x7FFFFFFF
		# a uniform -1..1 sample from the LCG
		var u := (float(lcg) / float(0x7FFFFFFF)) * 2.0 - 1.0
		lp = lp + a * (u - lp)
		var env: float = _envelope(i, frames, attack)
		samples[i] = lp * env * clampf(amp, 0.0, 1.0)
	return _wav_from_samples(samples)

## Frame count for a duration, hard-capped so a junk duration can never
## allocate a giant buffer.
func _frames_for(seconds: float) -> int:
	var s: float = _clamp(seconds, 0.01, MAX_SECONDS, 0.15)
	var n := int(float(MIX_RATE) * s)
	return clampi(n, 1, MAX_FRAMES)

## The "theme" loop: an eight-note pentatonic phrase over a slow bass, all
## sine waves and all deterministic — the same brick always synthesises
## byte-identical music, like every other buffer in this module. Notes stop
## ~50 ms before their slot ends and the whole bar loops seamlessly, because
## a music box that clicks on every bar sounds broken, not retro.
func _wav_music() -> AudioStreamWAV:
	var frames := int(float(MIX_RATE) * MUSIC_SECONDS)
	if frames <= 0:
		return null
	var samples := PackedFloat32Array()
	samples.resize(frames)
	var rate := float(MIX_RATE)
	var note_len := MUSIC_SECONDS / 8.0
	var melody := [440.0, 523.25, 659.25, 587.33, 440.0, 392.0, 523.25, 659.25]
	var bass := [110.0, 110.0, 164.81, 110.0]
	var attack := maxi(int(0.015 * rate), 1)
	for n in melody.size():
		var freq := float(melody[n])
		var i0 := int(float(n) * note_len * rate)
		var i1 := mini(i0 + int((note_len - 0.05) * rate), frames)
		for i in range(i0, i1):
			var t := float(i - i0) / float(maxi(i1 - i0, 1))
			var env := clampf(float(i - i0) / float(attack), 0.0, 1.0) * (1.0 - t)
			var ph := float(i) * freq * TAU / rate
			samples[i] += sin(ph) * env * 0.30 + sin(ph * 2.0) * env * 0.08
	var bar_len := MUSIC_SECONDS / float(bass.size())
	for b in bass.size():
		var freq := float(bass[b])
		var i0 := int(float(b) * bar_len * rate)
		var i1 := mini(i0 + int((bar_len - 0.05) * rate), frames)
		for i in range(i0, i1):
			var t := float(i - i0) / float(maxi(i1 - i0, 1))
			var env := clampf(float(i - i0) / float(attack * 4), 0.0, 1.0) * (1.0 - t * 0.8)
			samples[i] += sin(float(i) * freq * TAU / rate) * env * 0.22
	var wav := _wav_from_samples(samples)
	if wav == null:
		return null
	# the seam: loop the whole buffer (loop_end 0 would mean "no loop points")
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav

## Attack/decay envelope: linear ramp up over `attack` frames, exponential
## decay after. 1.0 at the start, ~0.0 at the end, never negative.
func _envelope(i: int, n: int, attack: int) -> float:
	if n <= 1:
		return 1.0
	var env: float
	if i < attack:
		env = float(i) / float(attack)
	else:
		var t := float(i - attack) / float(max(n - attack, 1))
		env = pow(1.0 - t, 2.0)
	return max(env, 0.0)

## Pack float samples (-1..1) into 16-bit signed little-endian mono PCM and
## wrap them in an AudioStreamWAV. Format facts used here were verified:
## FORMAT_16_BITS = 1, data is 2 bytes per frame when stereo is false,
## little-endian, signed.
func _wav_from_samples(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	if n <= 0:
		return null
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := samples[i]
		if is_nan(v) or is_inf(v):
			v = 0.0
		var s := int(clampf(v * PEAK16 * 32767.0, -32768.0, 32767.0))
		data[i * 2] = s & 0xFF
		data[(i * 2) + 1] = (s >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	return wav

# ---------------------------------------------------------------------------
# The generated play_on_start script
# ---------------------------------------------------------------------------

## The entity node's script. It holds NO audio logic itself — the player is
## its child — it only decides whether the sound fires when the scene
## starts. play_on_start = false leaves the player silent until something
## calls Player.play() (e.g. a later brick triggering the group).
func _ready_source(play_on_start: bool) -> String:
	var L: Array[String] = []
	L.append("extends Node")
	L.append("# Generated by EasyForge from an 'Audio' brick.")
	L.append("# play_on_start = %s" % ("true" if play_on_start else "false"))
	L.append("# The player is a child; this script only decides whether it")
	L.append("# fires on scene start. With play_on_start off the sound stays")
	L.append("# silent until another brick calls play() on it.")
	L.append("func _ready() -> void:")
	if play_on_start:
		L.append("	var p = _player()")
		L.append("	if p != null and not p.playing:")
		L.append("		p.play()")
	else:
		L.append("	pass")
	L.append("")
	L.append("## The routed player (2D or 3D) attached to this brick.")
	L.append("func _player() -> Node:")
	L.append("	for ch in get_children():")
	L.append("		if ch is AudioStreamPlayer or ch is AudioStreamPlayer2D or ch is AudioStreamPlayer3D:")
	L.append("			return ch")
	L.append("	return null")
	return "\n".join(L) + "\n"

# ---------------------------------------------------------------------------
# Defensive readers — a brick with missing/null/wrong-typed params still
# compiles to something harmless. Mirrors the FeatureCtx contract.
# ---------------------------------------------------------------------------

func _num(d: Dictionary, key: String, fallback: float) -> float:
	var x = d.get(key)
	if x is float or x is int:
		var f := float(x)
		return fallback if (is_nan(f) or is_inf(f)) else f
	if x is String and str(x).is_valid_float():
		var f2 := float(x)
		return fallback if (is_nan(f2) or is_inf(f2)) else f2
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

## A choice param, lowercased and validated against the allowed list.
func _choice(d: Dictionary, key: String, allowed: Array, fallback: String) -> String:
	var s := _str(d, key, fallback).to_lower()
	return s if s in allowed else fallback

func _clamp(v: float, lo: float, hi: float, fallback: float) -> float:
	if is_nan(v) or is_inf(v):
		return fallback
	return clampf(float(v), lo, hi)

func _f(x, fallback: float = 0.0) -> float:
	var r: float = _num({"v": x}, "v", fallback)
	return r

func _vec2_of(v, fallback: Vector2) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(_f(v[0], fallback.x), _f(v[1], fallback.y))
	return fallback

func _vec3_of(v, fallback: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(_f(v[0], fallback.x), _f(v[1], fallback.y), _f(v[2], fallback.z))
	# a 2-number position is legal in 3D too: treat it as x/y on the ground
	if v is Array and v.size() >= 2:
		return Vector3(_f(v[0], fallback.x), _f(v[1], fallback.y), fallback.z)
	return fallback

# ---------------------------------------------------------------------------
# Context helpers
# ---------------------------------------------------------------------------

func _is_3d(ctx, root: Node) -> bool:
	if ctx != null and ctx is Dictionary:
		var v = ctx.get("is_3d")
		if v is bool:
			return v
	if root != null and is_instance_valid(root):
		return root is Node3D
	return true

func _ctxv(ctx, key: String, default_value):
	if ctx is Dictionary:
		var v = (ctx as Dictionary).get(key)
		return v if v != null else default_value
	if ctx != null:
		for prop in ctx.get_property_list():
			if str(prop.get("name", "")) == key:
				return ctx.get(key)
	return default_value
