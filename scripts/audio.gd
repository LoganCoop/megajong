class_name Sfx
extends Node
## Procedural chiptune audio: every effect and the music loop are synthesized at startup,
## so the game needs no audio asset files. Press M (or the sound button) to mute.

const RATE := 22050
const MUSIC_RATE := 16000
const VOICES := 8

var muted := false
var _sounds: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music: AudioStreamPlayer


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	_build_sounds()
	_music = AudioStreamPlayer.new()
	_music.stream = _build_music()
	_music.volume_db = -16.0
	add_child(_music)
	_music.play()


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


func play(sound: String, pitch := 1.0) -> void:
	if muted or not _sounds.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sounds[sound]
	p.pitch_scale = pitch
	p.play()


# ---------------------------------------------------------------- Synthesis

static func _wave(kind: String, phase: float) -> float:
	var ph := fposmod(phase, 1.0)
	match kind:
		"square":
			return 1.0 if ph < 0.5 else -1.0
		"pulse":
			return 1.0 if ph < 0.25 else -1.0
		"tri":
			return 4.0 * absf(ph - 0.5) - 1.0
		"noise":
			return randf() * 2.0 - 1.0
	return sin(ph * TAU)


## Adds a note into `buf` starting at `start` (seconds). Frequency glides from f0 to f1.
static func _note(buf: PackedFloat32Array, rate: int, start: float, dur: float, f0: float, f1: float,
		kind: String, vol: float, decay := 6.0) -> void:
	var first := int(start * rate)
	var count := int(dur * rate)
	var phase := 0.0
	for i in count:
		if first + i >= buf.size():
			break
		var t := float(i) / count
		phase += lerpf(f0, f1, t) / rate
		var env := exp(-decay * t) * minf(1.0, float(i) / 40.0)
		buf[first + i] += _wave(kind, phase) * vol * env


static func _blank(seconds: float, rate: int) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * rate))
	return b


static func _to_stream(buf: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = buf.size()
	return s


static func _midi(n: int) -> float:
	return 440.0 * pow(2.0, (n - 69) / 12.0)


func _make(seconds: float, notes: Array) -> AudioStreamWAV:
	var b := _blank(seconds, RATE)
	for n: Array in notes:
		_note(b, RATE, n[0], n[1], n[2], n[3], n[4], n[5], n[6] if n.size() > 6 else 6.0)
	return _to_stream(b, RATE)


func _build_sounds() -> void:
	_sounds["select"] = _make(0.07, [[0.0, 0.06, 880.0, 1000.0, "square", 0.3, 5.0]])
	_sounds["deselect"] = _make(0.07, [[0.0, 0.06, 620.0, 500.0, "square", 0.25, 5.0]])
	_sounds["ui"] = _make(0.06, [[0.0, 0.05, 700.0, 760.0, "pulse", 0.25, 6.0]])
	_sounds["draw"] = _make(0.14, [
		[0.0, 0.12, 0.0, 0.0, "noise", 0.12, 8.0],
		[0.0, 0.12, 420.0, 760.0, "tri", 0.3, 4.0]])
	_sounds["discard"] = _make(0.16, [
		[0.0, 0.05, 0.0, 0.0, "noise", 0.3, 10.0],
		[0.0, 0.14, 300.0, 120.0, "tri", 0.45, 5.0]])
	_sounds["tick"] = _make(0.08, [[0.0, 0.07, 988.0, 988.0, "pulse", 0.3, 5.0]])
	_sounds["meld"] = _make(0.5, [
		[0.0, 0.14, _midi(72), _midi(72), "pulse", 0.3, 4.0],
		[0.07, 0.14, _midi(76), _midi(76), "pulse", 0.3, 4.0],
		[0.14, 0.14, _midi(79), _midi(79), "pulse", 0.3, 4.0],
		[0.21, 0.28, _midi(84), _midi(84), "pulse", 0.35, 4.0]])
	_sounds["surge"] = _make(0.3, [
		[0.0, 0.1, _midi(79), _midi(79), "square", 0.25, 4.0],
		[0.09, 0.2, _midi(86), _midi(86), "square", 0.3, 4.0]])
	_sounds["power"] = _make(0.45, [
		[0.0, 0.4, 250.0, 1400.0, "square", 0.25, 3.0],
		[0.0, 0.4, 125.0, 700.0, "tri", 0.3, 3.0]])
	_sounds["found"] = _make(0.35, [
		[0.0, 0.1, _midi(76), _midi(76), "tri", 0.4, 3.0],
		[0.08, 0.1, _midi(83), _midi(83), "tri", 0.4, 3.0],
		[0.16, 0.18, _midi(88), _midi(88), "tri", 0.4, 3.0]])
	_sounds["steal"] = _make(0.4, [[0.0, 0.35, 700.0, 90.0, "square", 0.3, 3.0]])
	_sounds["error"] = _make(0.22, [
		[0.0, 0.18, 150.0, 110.0, "square", 0.35, 3.0],
		[0.0, 0.18, 155.0, 112.0, "pulse", 0.25, 3.0]])
	_sounds["hint"] = _make(0.2, [
		[0.0, 0.08, 1320.0, 1320.0, "tri", 0.3, 5.0],
		[0.08, 0.1, 1760.0, 1760.0, "tri", 0.3, 5.0]])
	_sounds["round"] = _make(0.6, [
		[0.0, 0.15, _midi(57), _midi(57), "pulse", 0.3, 3.0],
		[0.15, 0.15, _midi(64), _midi(64), "pulse", 0.3, 3.0],
		[0.3, 0.3, _midi(69), _midi(69), "pulse", 0.35, 3.0]])
	var out: Array = []
	for i in 6:
		var n: int = [72, 76, 79, 84, 79, 88][i]
		out.append([i * 0.1, 0.25 if i == 5 else 0.12, _midi(n), _midi(n), "pulse", 0.35, 3.0])
		out.append([i * 0.1, 0.25 if i == 5 else 0.12, _midi(n - 12), _midi(n - 12), "tri", 0.4, 3.0])
	_sounds["out"] = _make(1.1, out)


func _build_music() -> AudioStreamWAV:
	var bpm := 108.0
	var eighth := 60.0 / bpm / 2.0
	# Am - F - C - G, two passes; the second pass adds a lead line.
	var chords := [
		[45, [57, 60, 64]],
		[41, [53, 57, 60]],
		[48, [60, 64, 67]],
		[43, [55, 59, 62]],
	]
	var lead := [
		[81, 0, 2], [84, 2, 2], [83, 4, 2], [81, 6, 2],
		[77, 0, 3], [79, 3, 1], [81, 4, 4],
		[76, 0, 2], [79, 2, 2], [84, 4, 3], [83, 7, 1],
		[79, 0, 2], [83, 2, 2], [86, 4, 2], [83, 6, 2],
	]
	var bars := 8
	var b := _blank(bars * 8 * eighth, MUSIC_RATE)
	for bar in bars:
		var ch: Array = chords[bar % 4]
		var tones: Array = ch[1]
		var t0 := bar * 8 * eighth
		for step in 8:
			var t := t0 + step * eighth
			if step % 2 == 0:
				_note(b, MUSIC_RATE, t, eighth * 1.6, _midi(ch[0]), _midi(ch[0]), "square", 0.16, 2.5)
			var arp: int = tones[[0, 1, 2, 1][step % 4]] + (12 if step >= 4 else 0)
			_note(b, MUSIC_RATE, t, eighth * 0.9, _midi(arp), _midi(arp), "pulse", 0.07, 3.5)
			if step % 2 == 1:
				_note(b, MUSIC_RATE, t, eighth * 0.4, 0.0, 0.0, "noise", 0.05, 8.0)
			if step % 4 == 0:
				_note(b, MUSIC_RATE, t, eighth * 0.5, 160.0, 50.0, "tri", 0.3, 5.0)
		if bar >= 4:
			for l: Array in lead.slice((bar % 4) * 4, (bar % 4) * 4 + 4):
				_note(b, MUSIC_RATE, t0 + l[1] * eighth, l[2] * eighth, _midi(l[0]), _midi(l[0]), "tri", 0.2, 2.0)
	return _to_stream(b, MUSIC_RATE, true)
