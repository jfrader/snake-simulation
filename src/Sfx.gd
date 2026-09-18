extends Node

# Sound effects, synthesized at startup so the game stays code-only: no new
# assets, no network, and the shapes are tunable from here.
#
# The Gamestruments addon is music only, so nothing here goes through it. Both
# the effects and the generated music currently land on Master, since the
# project defines no other buses; if a `Music` bus is ever added the kit prefers
# it automatically and will part company with the effects on its own.

const MIX_RATE := 22050
const NOISE_SEED := 0x5EED5F1E

const EAT_DB := -11.0
const DEATH_DB := -8.0
# The movement bed has to be barely there: it never rises above a whisper.
# The caller passes motion normalised over the snake's actual speed range, so
# the quiet end is reachable rather than theoretical.
const SLITHER_DB := -34.0
const SLITHER_DB_AT_SPEED := -27.0

const EAT_SECONDS := 0.085
const DEATH_SECONDS := 0.7
const SLITHER_SECONDS := 1.2

var eat_player: AudioStreamPlayer
var death_player: AudioStreamPlayer
var slither_player: AudioStreamPlayer

var _moving := false
# Fixed seed, and never the global RNG: Scene draws its per-launch salt from
# that, so spending draws here would silently change every run's seed.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = NOISE_SEED
	eat_player = _make_player(_eat_stream(), EAT_DB)
	death_player = _make_player(_death_stream(), DEATH_DB)
	# A gentle bed while the snake moves, at a level you should have to listen for.
	slither_player = _make_player(_slither_stream(), SLITHER_DB)
	slither_player.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	slither_player.stream.loop_begin = 0
	# Frame count from the actual data: the seamless blend trims the tail.
	slither_player.stream.loop_end = slither_player.stream.data.size() / 2


func _exit_tree() -> void:
	release()


# Stops the players AND drops their streams. Shutdown only: it leaves the
# effects unusable. Releasing the streams before the tree starts coming down is
# what keeps the exit clean; doing it during teardown races the audio thread.
func release() -> void:
	for player in _players():
		if player.playing:
			player.stop()
		player.stream = null


func _players() -> Array:
	return [eat_player, death_player, slither_player]


func _make_player(stream: AudioStreamWAV, volume_db: float) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	add_child(player)
	return player


# --- public API ---------------------------------------------------------------

# Pitched by what was eaten, so a banana sounds different from an apple.
func play_eat(value: int) -> void:
	if eat_player == null:
		return
	eat_player.pitch_scale = 0.92 + clampf(float(value), 1.0, 3.0) * 0.12
	eat_player.play()


func play_death() -> void:
	if death_player == null:
		return
	death_player.play()


func set_moving(moving: bool) -> void:
	_moving = moving
	if slither_player == null:
		return
	if moving:
		if not slither_player.playing:
			slither_player.play()
	else:
		slither_player.stop()


# Volume and pitch follow the snake's speed, so the bed reads as motion rather
# than as a separate sound.
func update_motion(speed_ratio: float) -> void:
	if slither_player == null or not _moving:
		return
	var t = clampf(speed_ratio, 0.0, 1.0)
	slither_player.volume_db = lerpf(SLITHER_DB, SLITHER_DB_AT_SPEED, t)
	slither_player.pitch_scale = lerpf(0.85, 1.25, t)


# --- synthesis ---------------------------------------------------------------

func _eat_stream() -> AudioStreamWAV:
	var count = int(MIX_RATE * EAT_SECONDS)
	var samples = PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in range(count):
		var t = float(i) / MIX_RATE
		var progress = t / EAT_SECONDS
		# A short blip that rises and snaps shut.
		var frequency = 560.0 + 820.0 * progress
		phase += TAU * frequency / MIX_RATE
		var envelope = exp(-t * 46.0)
		samples[i] = sin(phase) * envelope * 0.55
	return _to_wav(samples)


func _death_stream() -> AudioStreamWAV:
	var count = int(MIX_RATE * DEATH_SECONDS)
	var samples = PackedFloat32Array()
	samples.resize(count)
	var phase := 0.0
	for i in range(count):
		var t = float(i) / MIX_RATE
		var progress = t / DEATH_SECONDS
		# Falling pitch with a breath of noise under it.
		var frequency = 430.0 * (1.0 - 0.78 * progress)
		phase += TAU * frequency / MIX_RATE
		var envelope = exp(-t * 4.2)
		var noise = _rng.randf() * 2.0 - 1.0
		samples[i] = (sin(phase) * 0.62 + noise * 0.14) * envelope * 0.5
	return _to_wav(samples)


# Low-passed noise, crossfaded head-to-tail so the loop has no seam.
func _slither_stream() -> AudioStreamWAV:
	var count = _slither_frames()
	var raw = PackedFloat32Array()
	raw.resize(count)
	var previous := 0.0
	for i in range(count):
		# One-pole low pass: keeps it a soft hiss instead of bright static.
		previous = lerpf(previous, _rng.randf() * 2.0 - 1.0, 0.06)
		# Slow swell so it breathes rather than drones.
		var swell = 0.65 + 0.35 * sin(TAU * 1.5 * float(i) / MIX_RATE)
		raw[i] = previous * swell * 0.5
	return _to_wav(_seamless(raw))


func _slither_frames() -> int:
	return int(MIX_RATE * SLITHER_SECONDS)


func _seamless(samples: PackedFloat32Array) -> PackedFloat32Array:
	# Blend the tail into the head, then drop the tail, so looping is inaudible.
	var count = samples.size()
	var fade = int(count * 0.2)
	for i in range(fade):
		var blend = float(i) / float(fade)
		samples[i] = samples[i] * blend + samples[count - fade + i] * (1.0 - blend)
	samples.resize(count - fade)
	return samples


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		bytes.encode_s16(i * 2, int(round(clampf(samples[i], -1.0, 1.0) * 32767.0)))
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
