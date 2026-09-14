extends Node
## The soundtrack: the browser game's procedural synth engine (MUSIC_PROC in belt-runner-3d.html), ported note for
## note. Eight tracks, each a pad colour (five chord voices of detuned oscillators through one slowly breathing
## lowpass), a sub, an echo whose time follows the tempo, ambient layers (sparkle, wind, a wandering melody, a pulse,
## a choir swell) and a groove (kick, snare or clap, rim, hats, shaker, bass, arp, chord stabs, a lead). It drifts in
## ambient mode for two or three minutes, brings the groove on for a minute or so, then fades it and moves to the
## next track. Everything is rendered here, sample by sample, on its own thread into an AudioStreamGenerator, so the
## timing is sample-accurate as Web Audio's scheduling was; the pads are resampled from loops rendered once per recipe.

signal groove_started(track_name: String)
signal track_changed(track_name: String)

const RATE := 22050
const CHUNK := 256
const TABLE := 2048
const OUT_GAIN := 0.55

const PADS := {
	"warm":    [["triangle", 0.0, 0.6, 1.0], ["sawtooth", 6.0, 0.09, 1.0], ["sawtooth", -6.0, 0.09, 1.0]],
	"glass":   [["sine", 0.0, 0.5, 1.0], ["sine", 3.0, 0.28, 2.0], ["sine", -4.0, 0.14, 4.0], ["triangle", 0.0, 0.08, 1.0]],
	"strings": [["sawtooth", 14.0, 0.16, 1.0], ["sawtooth", -14.0, 0.16, 1.0], ["sawtooth", 0.0, 0.12, 1.0], ["triangle", 0.0, 0.22, 1.0]],
	"organ":   [["square", 0.0, 0.14, 1.0], ["sine", 0.0, 0.42, 1.0], ["sine", 0.0, 0.2, 2.0], ["sine", 0.0, 0.12, 3.0]],
	"hollow":  [["triangle", 0.0, 0.5, 1.0], ["triangle", 8.0, 0.26, 2.0], ["square", 0.0, 0.05, 0.5]],
}
const MAJ := [0, 2, 4, 7, 9, 12, 14, 16]
const DOR := [0, 2, 3, 5, 7, 9, 10, 12, 14]
const MINP := [0, 3, 5, 7, 10, 12, 15, 17]
const LYD := [0, 2, 4, 6, 7, 9, 11, 12, 14]
const AEO := [0, 2, 3, 5, 7, 8, 10, 12, 14]

static func hz(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


static func ch(root: int, n: Array) -> Dictionary:
	var notes: Array = []
	for m in n:
		notes.append(hz(m))
	return {"root": hz(root), "rootMidi": root, "notes": notes}


var TRACKS: Array = [
	{"name": "Drift", "bpm": 112, "pad": "warm", "padCut": 520.0, "lfo": 0.06, "subWave": "sine", "echo": 3, "ambient": {"sparkle": 0.07, "sparkleWave": "sine", "wind": 0.012}, "scale": DOR, "melodyWave": "sine",
	 "chords": [ch(38, [50, 53, 57, 60, 64]), ch(34, [46, 50, 53, 57, 60]), ch(41, [53, 57, 60, 64, 67]), ch(36, [48, 52, 55, 59, 62])],
	 "groove": {"kick": [0, 4], "fill": true, "snare": [2, 6], "hat": "8", "openHat": [3], "bassWave": "sawtooth", "bass": [[0, 1.0], [3, 1.0], [4, 1.5], [6, 2.0], [7, 0.75]], "arpWave": "square", "arpVol": 0.045, "arp": [0, 2, 4, 2, 1, 3, 4, 3]}},
	{"name": "Halcyon", "bpm": 96, "pad": "glass", "padCut": 900.0, "lfo": 0.045, "subWave": "", "echo": 4, "ambient": {"melody": 0.16, "sparkle": 0.03, "sparkleWave": "triangle"}, "scale": MAJ, "melodyWave": "sine",
	 "chords": [ch(40, [52, 55, 59, 62, 66]), ch(36, [48, 52, 55, 59, 64]), ch(43, [55, 59, 62, 66, 69]), ch(38, [50, 54, 57, 60, 64])],
	 "groove": {"kick": [], "snare": [], "hat": "off", "shaker": true, "bassWave": "triangle", "bass": [[0, 1.0], [4, 1.0], [6, 1.5]], "arpWave": "triangle", "arpVol": 0.09, "arp": [0, 1, 2, 3, 4, 3, 2, 1], "pluck": true, "lead": true}},
	{"name": "Aurum", "bpm": 118, "pad": "organ", "padCut": 700.0, "lfo": 0.08, "subWave": "triangle", "echo": 2, "ambient": {"wind": 0.03, "pulse": true}, "scale": MINP, "melodyWave": "triangle",
	 "chords": [ch(33, [45, 48, 52, 55, 59]), ch(41, [53, 57, 60, 64, 67]), ch(36, [48, 52, 55, 59, 62]), ch(43, [55, 59, 62, 65, 69])],
	 "groove": {"kick": [0, 3, 6], "fill": true, "snare": [2, 5, 7], "clap": true, "hat": "16", "openHat": [7], "bassWave": "square", "bass": [[0, 1.0], [1, 1.0], [3, 2.0], [6, 1.5]], "arp": null, "stab": [0, 3, 6], "stabWave": "sawtooth"}},
	{"name": "Frost", "bpm": 80, "pad": "strings", "padCut": 380.0, "lfo": 0.035, "subWave": "sine", "echo": 4, "ambient": {"sparkle": 0.11, "sparkleWave": "sine", "melody": 0.06, "choir": true}, "scale": AEO, "melodyWave": "triangle",
	 "chords": [ch(35, [47, 50, 54, 57, 61]), ch(43, [55, 59, 62, 66, 69]), ch(38, [50, 54, 57, 61, 64]), ch(45, [57, 61, 64, 68, 71])],
	 "groove": {"kick": [0, 5], "fill": false, "snare": [4], "hat": "8", "bassWave": "sine", "bass": [[0, 1.0], [5, 1.0], [6, 1.5]], "arp": null, "stab": [0, 4], "stabWave": "sine", "lead": true}},
	{"name": "Sable", "bpm": 150, "pad": "hollow", "padCut": 300.0, "lfo": 0.1, "subWave": "sine", "echo": 3, "ambient": {"wind": 0.03, "sparkle": 0.03, "sparkleWave": "square"}, "scale": MINP, "melodyWave": "square",
	 "chords": [ch(37, [49, 52, 56, 59, 63]), ch(33, [45, 49, 52, 56, 59]), ch(40, [52, 56, 59, 63, 66]), ch(35, [47, 51, 54, 58, 61])],
	 "groove": {"kick": [0, 2, 5], "fill": true, "snare": [4], "hat": "16", "openHat": [1, 3, 5, 7], "bassWave": "sawtooth", "bass": [[0, 1.0], [1, 1.0], [2, 1.0], [3, 1.5], [5, 1.0], [6, 2.0], [7, 1.5]], "arpWave": "sawtooth", "arpVol": 0.03, "arp": [0, 0, 2, 2, 4, 4, 3, 1]}},
	{"name": "Cinder", "bpm": 100, "pad": "warm", "padCut": 480.0, "lfo": 0.05, "subWave": "triangle", "echo": 3, "ambient": {"pulse": true, "sparkle": 0.04, "sparkleWave": "sine"}, "scale": DOR, "melodyWave": "sine",
	 "chords": [ch(31, [43, 46, 50, 53, 57]), ch(39, [51, 55, 58, 62, 65]), ch(34, [46, 50, 53, 57, 60]), ch(41, [53, 57, 60, 64, 67])],
	 "groove": {"kick": [0, 4, 7], "fill": false, "snare": [], "rim": [2, 6], "hat": "8", "brush": true, "bassWave": "sine", "bass": [[0, 1.0], [2, 0.75], [4, 1.5], [7, 2.0]], "arp": null, "stab": [1, 4, 6], "stabWave": "triangle"}},
	{"name": "Meridian", "bpm": 124, "pad": "organ", "padCut": 820.0, "lfo": 0.07, "subWave": "sine", "echo": 2, "ambient": {"choir": true, "melody": 0.1, "sparkle": 0.05, "sparkleWave": "sine"}, "scale": LYD, "melodyWave": "triangle",
	 "chords": [ch(36, [48, 52, 55, 59, 62]), ch(43, [55, 59, 62, 66, 69]), ch(45, [57, 60, 64, 67, 71]), ch(41, [53, 57, 60, 64, 67])],
	 "groove": {"kick": [0, 2, 4, 6], "fill": true, "snare": [2, 6], "clap": true, "hat": "8", "openHat": [1, 3, 5, 7], "bassWave": "square", "bass": [[0, 1.0], [2, 1.0], [3, 2.0], [4, 1.0], [6, 1.5], [7, 1.0]], "arpWave": "triangle", "arpVol": 0.05, "arp": [0, 2, 4, 7, 4, 2, 0, 3], "lead": true}},
	{"name": "Umbra", "bpm": 72, "pad": "strings", "padCut": 260.0, "lfo": 0.03, "subWave": "sine", "echo": 4, "ambient": {"wind": 0.04, "melody": 0.05, "choir": true}, "scale": AEO, "melodyWave": "sine",
	 "chords": [ch(29, [41, 44, 48, 51, 55]), ch(37, [49, 52, 56, 59, 63]), ch(34, [46, 49, 53, 56, 60]), ch(32, [44, 47, 51, 54, 58])],
	 "groove": {"kick": [0, 6], "fill": false, "snare": [4], "hat": "off", "shaker": true, "bassWave": "square", "bass": [[0, 1.0], [6, 0.75]], "arp": null, "stab": [0], "stabWave": "triangle", "lead": true}},
]

# ---- state (owned by the render thread once it starts; the main thread only reads the readouts and sets the switches)
var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _thread: Thread
var _running := false
var _tables := {}            # wave -> PackedFloat32Array (one cycle)
var _pad_loops := {}         # recipe -> PackedFloat32Array (a loop at PAD_REF Hz)
var _hits := {}              # key -> PackedFloat32Array (a rendered noise hit)
var _noise := PackedFloat32Array()
const PAD_REF := 110.0
const PAD_LOOP := 4.0
var _pos := 0                # samples rendered
var _step := 0
var _next := 0.0             # sample time of the next step
var _step_len := 0.0         # seconds
var _mode := "ambient"
var _mode_until := 0.0
var _chord := 0
var _track := 0
var _voices: Array = []      # one-shots: {kind, ...}
var _pads: Array = []        # pad voices: {loop, ph, f, f_target, tau, g, g_target, g_tau, dying, k, mult}
var _pad_gain := 0.0
var _pad_gain_target := 0.16
var _pad_gain_tau := 4.0
var _pad_gain_wait := 0.5
var _cut := 520.0
var _cut_target := 520.0
var _cut_tau := 0.01
var _lfo_f := 0.06
var _lfo_target := 0.06
var _lfo_tau := 0.01
var _lfo_ph := 0.0
var _sub_ph := 0.0
var _sub_f := 55.0
var _sub_target := 55.0
var _sub_tau := 0.01
var _sub_g := 0.0
var _sub_target_g := 0.0
var _sub_wave := "sine"
var _groove_g := 0.0
var _groove_target := 0.0
var _groove_tau := 1.2
var _mel_deg := 3
var _mel_until := 0.0
var _delay := PackedFloat32Array()
var _delay_pos := 0
var _delay_len := 1.0
var _delay_len_target := 1.0
var _delay_lp := 0.0
var _fx1 := 0.0   # pad filter state
var _fx2 := 0.0
var _fy1 := 0.0
var _fy2 := 0.0
var _out_gain := OUT_GAIN
var _out_target := OUT_GAIN
var _mix := PackedFloat32Array()
var _echo_in := PackedFloat32Array()
var _pad_mix := PackedFloat32Array()
var _frames := PackedVector2Array()
var _mutex := Mutex.new()
var _pending_events: Array = []   # names to emit on the main thread
var _rng := RandomNumberGenerator.new()
# readouts for the smoke run
var ready_for_smoke := false
var voices_peak := 0
var out_peak := 0.0            # loudest sample rendered so far, for the smoke print
var render_usec := 0           # thread time spent rendering, to compare with the audio time rendered


func _ready() -> void:
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.5
	_player.stream = gen
	_player.bus = "Master"
	add_child(_player)
	apply_settings()
	_player.play()
	_playback = _player.get_stream_playback()
	if _playback == null:
		push_warning("Music: no audio playback available, the soundtrack stays silent")
		return
	_mix.resize(CHUNK)
	_echo_in.resize(CHUNK)
	_pad_mix.resize(CHUNK)
	_frames.resize(CHUNK)
	_delay.resize(RATE * 3)
	_running = true
	_thread = Thread.new()
	_thread.start(_run)


func _exit_tree() -> void:
	_running = false
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func _process(_dt: float) -> void:
	_mutex.lock()
	var ev: Array = _pending_events.duplicate()
	_pending_events.clear()
	_mutex.unlock()
	for e in ev:
		if e[0] == "groove":
			groove_started.emit(e[1])
		else:
			track_changed.emit(e[1])


## The menu's music switch and volume (its own path to the speakers: the browser's music slider is independent).
func apply_settings() -> void:
	var s: Dictionary = State.settings
	var on: bool = bool(s.get("music", true))
	_out_target = (OUT_GAIN * clampf(float(s.get("music_volume", 1.0)), 0.0, 1.0)) if on else 0.0


func track_name() -> String:
	return str(TRACKS[_track]["name"])


func mode() -> String:
	return _mode


func step() -> int:
	return _step


# ---- the render thread
func _run() -> void:
	_build_tables()
	_build_pad_loops()
	_build_noise()
	_init_song()
	ready_for_smoke = true
	while _running:
		var avail: int = _playback.get_frames_available()
		if avail >= CHUNK:
			var n: int = min(avail, CHUNK * 8)
			while n >= CHUNK:
				_render_chunk()
				n -= CHUNK
		else:
			OS.delay_msec(4)


func _build_tables() -> void:
	for w in ["sine", "triangle", "square", "sawtooth"]:
		var t := PackedFloat32Array()
		t.resize(TABLE)
		for i in TABLE:
			var ph: float = float(i) / TABLE
			var v: float
			match w:
				"sine": v = sin(ph * TAU)
				"triangle": v = 1.0 - 4.0 * absf(ph - 0.5) if ph < 1.0 else 0.0
				"square": v = 1.0 if ph < 0.5 else -1.0
				_: v = 2.0 * ph - 1.0
			t[i] = v
		_tables[w] = t


## A pad recipe rendered once at PAD_REF Hz as a loop: every chord voice plays it back at its own pitch.
func _build_pad_loops() -> void:
	var n := int(PAD_LOOP * RATE)
	var fade := int(0.25 * RATE)
	for name in PADS:
		var recipe: Array = PADS[name]
		var buf := PackedFloat32Array()
		buf.resize(n)
		for osc in recipe:
			var tbl: PackedFloat32Array = _tables[osc[0]]
			var f: float = PAD_REF * pow(2.0, float(osc[1]) / 1200.0) * float(osc[3])
			var g: float = osc[2]
			var ph := 0.0
			var inc: float = f / RATE
			for i in n:
				buf[i] += tbl[int(ph * TABLE) % TABLE] * g
				ph += inc
				if ph >= 1.0:
					ph -= 1.0
		# a crossfade at the end so the loop joins cleanly
		for i in fade:
			var a: float = float(i) / fade
			buf[n - fade + i] = buf[n - fade + i] * (1.0 - a) + buf[i] * a
		_pad_loops[name] = buf


func _build_noise() -> void:
	_noise.resize(65536)
	for i in 65536:
		_noise[i] = _rng.randf_range(-1.0, 1.0)


func _init_song() -> void:
	_track = _rng.randi() % TRACKS.size()
	_apply_track(0.01)
	_pad_gain_wait = 0.5
	_next = 0.2 * RATE
	_mode_until = _rng.randf_range(120.0, 200.0)


func _K() -> Dictionary:
	return TRACKS[_track]


func _t() -> float:
	return float(_pos) / RATE


# ---- the track: pad recipe, filter, sub, echo time, first chord
func _apply_track(glide: float) -> void:
	var K := _K()
	_step_len = 60.0 / float(K["bpm"]) / 2.0
	_chord = 0
	_delay_len_target = _step_len * float(K["echo"])
	_cut_target = K["padCut"]
	_cut_tau = glide
	_lfo_target = K["lfo"]
	_lfo_tau = glide
	_build_pad(str(K["pad"]))
	_sub_wave = str(K["subWave"]) if str(K["subWave"]) != "" else "sine"
	_sub_target_g = 0.0 if str(K["subWave"]) == "" else (0.14 if str(K["subWave"]) == "sine" else 0.09)
	_set_chord(0, glide)


func _build_pad(recipe: String) -> void:
	for v in _pads:
		v["dying"] = true
		v["g_target"] = 0.0
		v["g_tau"] = 0.8
		v["die_at"] = _pos + 4 * RATE
	var loop: PackedFloat32Array = _pad_loops[recipe]
	for k in 5:
		_pads.append({"loop": loop, "ph": _rng.randf() * loop.size(), "f": 220.0, "f_target": 220.0, "tau": 0.01, "g": 0.0, "g_target": 0.2, "g_tau": 1.5, "dying": false, "die_at": 0, "k": k})


func _set_chord(i: int, glide: float) -> void:
	_chord = i
	var C: Dictionary = _K()["chords"][i]
	for v in _pads:
		if v["dying"]:
			continue
		v["f_target"] = float(C["notes"][int(v["k"])])
		v["tau"] = glide
	_sub_target = C["root"]
	_sub_tau = glide


# ---- one-shot voices
func _note(wave: String, f: float, a: float, d: float, vol: float, to_echo: bool, groove: bool) -> void:
	_voices.append({"kind": "note", "tbl": _tables[wave], "f": f, "ph": 0.0, "a": a, "d": d, "vol": vol, "age": 0.0, "echo": to_echo, "groove": groove})


## A noise hit through a filter (bandpass / highpass / lowpass) with an exponential fade, rendered once per recipe.
func _hit(filter: String, freq: float, q: float, d: float, vol: float, to_echo: bool, groove: bool, delay: float = 0.0) -> void:
	var key := "%s:%d:%.1f:%.3f" % [filter, roundi(freq / 25.0) * 25, q, d]
	if not _hits.has(key):
		_hits[key] = _render_hit(filter, freq, q, d)
	_voices.append({"kind": "sample", "buf": _hits[key], "i": -int(delay * RATE), "vol": vol, "echo": to_echo, "groove": groove})


func _render_hit(filter: String, freq: float, q: float, d: float) -> PackedFloat32Array:
	var n := int((d + 0.05) * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var co := _biquad(filter, freq, q)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var start := _rng.randi() % 60000
	var decay: float = pow(0.0001, 1.0 / max(1.0, d * RATE))
	var env := 1.0
	for i in n:
		var x: float = _noise[(start + i) % 65536]
		var y: float = co[0] * x + co[1] * x1 + co[2] * x2 - co[3] * y1 - co[4] * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		buf[i] = y * env
		env *= decay
	return buf


## RBJ biquad coefficients [b0, b1, b2, a1, a2] normalised by a0.
func _biquad(kind: String, freq: float, q: float) -> PackedFloat32Array:
	var w0: float = TAU * clampf(freq, 10.0, RATE * 0.45) / RATE
	var cw := cos(w0)
	var sw := sin(w0)
	var alpha: float = sw / (2.0 * max(0.05, q))
	var b0: float
	var b1: float
	var b2: float
	match kind:
		"lowpass":
			b0 = (1.0 - cw) * 0.5
			b1 = 1.0 - cw
			b2 = (1.0 - cw) * 0.5
		"highpass":
			b0 = (1.0 + cw) * 0.5
			b1 = -(1.0 + cw)
			b2 = (1.0 + cw) * 0.5
		_:
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
	var a0: float = 1.0 + alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, (-2.0 * cw) / a0, (1.0 - alpha) / a0])


func _kick() -> void:
	var key := "kick"
	if not _hits.has(key):
		var n := int(0.32 * RATE)
		var buf := PackedFloat32Array()
		buf.resize(n)
		var ph := 0.0
		var tbl: PackedFloat32Array = _tables["sine"]
		var decay: float = pow(0.0001 / 0.7, 1.0 / (0.3 * RATE))
		var g := 0.7
		for i in n:
			var t: float = float(i) / RATE
			var f: float = 160.0 * pow(42.0 / 160.0, min(1.0, t / 0.11))
			buf[i] = tbl[int(ph * TABLE) % TABLE] * g
			ph += f / RATE
			if ph >= 1.0:
				ph -= 1.0
			g *= decay
		_hits[key] = buf
	_voices.append({"kind": "sample", "buf": _hits[key], "i": 0, "vol": 1.0, "echo": false, "groove": true})


## The bass: an oscillator through a lowpass (a sweep from 900 to 160 Hz for the buzzy waves) with its own envelope.
func _bass(f: float, wave: String) -> void:
	var sine: bool = wave == "sine"
	_voices.append({"kind": "bass", "tbl": _tables[wave], "f": f, "ph": 0.0, "sine": sine, "a": 0.01 if sine else 0.005, "d": min(0.6, _step_len * 1.8) if sine else min(0.24, _step_len * 0.9), "vol": 0.28 if sine else (0.14 if wave == "square" else 0.2), "age": 0.0, "x1": 0.0, "x2": 0.0, "y1": 0.0, "y2": 0.0, "echo": false, "groove": true})


func _stab(C: Dictionary, wave: String) -> void:
	for k in range(1, 5):
		_note(wave, float(C["notes"][k]), 0.01, 0.12 if wave == "sawtooth" else 0.3, 0.03 if wave == "sawtooth" else 0.05, false, true)


## A wandering lead: a random walk over the track's scale above the chord root, phrases with rests.
func _melody(K: Dictionary, C: Dictionary, vol: float, wave: String, groove: bool) -> void:
	var t := _t()
	if t < _mel_until:
		return
	var sc: Array = K["scale"]
	_mel_deg = clampi(_mel_deg + (-1 if _rng.randf() < 0.5 else 1) * (2 if _rng.randf() < 0.25 else 1), 0, sc.size() - 1)
	var f := hz(float(C["rootMidi"]) + 24.0 + float(sc[_mel_deg]))
	var r := _rng.randf()
	var len: float = _step_len * (4.0 if r < 0.3 else (2.0 if r < 0.65 else 1.0))
	_note(wave, f, 0.03, len * 1.4, vol, false, groove)
	_note(wave, f, 0.03, len * 1.4, vol * 0.5, true, groove)
	_mel_until = t + len + (_step_len * _rng.randf_range(4.0, 10.0) if _rng.randf() < 0.2 else 0.0)


# ---- the sequencer: one step of the pattern (schedule(s, t) in the browser)
func _schedule(s: int) -> void:
	var K := _K()
	var G: Dictionary = K["groove"]
	var A: Dictionary = K["ambient"]
	var bar := s % 8
	var t := _t()
	if s % 32 == 0 and s > 0:
		_set_chord((_chord + 1) % (K["chords"] as Array).size(), 0.05 if _mode == "groove" else 1.5)
	if bar == 0 and t > _mode_until:
		if _mode == "ambient":
			_mode = "groove"
			_mode_until = t + _rng.randf_range(60.0, 95.0)
			_groove_target = 1.0
			_groove_tau = 1.2
			_queue_event("groove", str(K["name"]))
		else:
			# groove over: fade it out and drift into the next track
			_mode = "ambient"
			_mode_until = t + _rng.randf_range(120.0, 200.0)
			_groove_target = 0.0
			_groove_tau = 2.5
			_track = (_track + 1) % TRACKS.size()
			_apply_track(2.5)
			K = _K()
			G = K["groove"]
			A = K["ambient"]
			_queue_event("track", str(K["name"]))
	var C: Dictionary = K["chords"][_chord]
	if _mode == "ambient":
		if A.has("sparkle") and _rng.randf() < float(A["sparkle"]):
			var f: float = float(C["notes"][_rng.randi() % 5]) * (2.0 if _rng.randf() < 0.5 else 4.0)
			_note(str(A["sparkleWave"]), f, 0.04, 1.8, 0.05, true, false)
			_note(str(A["sparkleWave"]), f, 0.04, 1.8, 0.035, false, false)
		if A.has("wind") and _rng.randf() < float(A["wind"]):
			_hit("bandpass", _rng.randf_range(200.0, 500.0), 1.5, 3.0, 0.06, false, false)
		if A.has("melody") and _rng.randf() < float(A["melody"]):
			_melody(K, C, 0.045, str(K["melodyWave"]), false)
		if A.get("pulse", false) and bar % 4 == 0:
			_note("triangle", float(C["root"]) * 2.0, 0.005, _step_len * 1.5, 0.06, false, false)
			_note("triangle", float(C["root"]) * 2.0, 0.005, _step_len * 1.5, 0.03, true, false)
		if A.get("choir", false) and s % 32 == 8:
			_note("sine", float(C["root"]) * 3.0, 3.0, 5.0, 0.05, false, false)
			_note("sine", float(C["root"]) * 3.0 * 1.005, 3.0, 5.0, 0.04, false, false)
	else:
		if (G["kick"] as Array).has(bar) or (bool(G.get("fill", false)) and bar == 7 and (s >> 3) % 4 == 3):
			_kick()
		if (G["snare"] as Array).has(bar):
			if G.get("clap", false):
				for dl in [0.0, 0.012, 0.026]:
					_hit("bandpass", 1500.0, 1.2, 0.12, 0.16, false, true, dl)
			else:
				_hit("bandpass", 1900.0, 0.9, 0.16, 0.22, false, true)
				_note("sine", 190.0, 0.002, 0.09, 0.14, false, true)
		if G.has("rim") and (G["rim"] as Array).has(bar):
			_hit("bandpass", 2600.0, 4.0, 0.05, 0.18, false, true)
		var hat: String = str(G["hat"])
		if hat == "16" or (hat == "8" and bar % 2 == 0):
			var brush: bool = G.get("brush", false)
			_hit("highpass", 4500.0 if brush else 7500.0, 0.7, 0.09 if brush else (0.05 if bar % 2 == 1 else 0.035), 0.05 if brush else (0.05 if bar % 2 == 1 else 0.08), false, true)
		if G.has("openHat") and (G["openHat"] as Array).has(bar):
			_hit("highpass", 6000.0, 0.7, 0.2, 0.05, false, true)
		if G.get("shaker", false):
			_hit("highpass", 9000.0, 0.5, 0.06, 0.05 if bar % 2 == 1 else 0.03, false, true)
		for bp in G["bass"]:
			if bar == int(bp[0]):
				_bass(float(C["root"]) * float(bp[1]), str(G["bassWave"]))
		if G.get("arp") != null:
			var arp: Array = G["arp"]
			var deg: int = arp[bar]
			var f: float = float(C["notes"][deg % 5]) * 2.0 * (2.0 if deg >= 5 else 1.0)
			var d: float = 0.35 if G.get("pluck", false) else 0.16
			_note(str(G["arpWave"]), f, 0.005, d, float(G["arpVol"]), false, true)
			_note(str(G["arpWave"]), f, 0.005, d, float(G["arpVol"]) * 0.65, true, true)
		if G.has("stab") and (G["stab"] as Array).has(bar):
			_stab(C, str(G["stabWave"]))
		if G.get("lead", false) and _rng.randf() < 0.35:
			_melody(K, C, 0.06, str(K["melodyWave"]), true)


func _queue_event(kind: String, name: String) -> void:
	_mutex.lock()
	_pending_events.append([kind, name])
	_mutex.unlock()


# ---- rendering: CHUNK samples at a time, split at step boundaries so every note starts on its sample
func _render_chunk() -> void:
	var t0 := Time.get_ticks_usec()
	var done := 0
	while done < CHUNK:
		var until_step: int = int(ceil(_next)) - _pos
		if until_step <= 0:
			_schedule(_step)
			_step += 1
			_next += _step_len * RATE
			continue
		var n: int = min(CHUNK - done, until_step)
		_render_span(done, n)
		done += n
		_pos += n
	for i in CHUNK:
		var v: float = _mix[i]
		if absf(v) > out_peak:
			out_peak = absf(v)
		_frames[i] = Vector2(v, v)
	_playback.push_buffer(_frames)
	render_usec += Time.get_ticks_usec() - t0


static func _approach(v: float, target: float, tau: float, dt: float) -> float:
	if tau <= 0.0001:
		return target
	return v + (target - v) * (1.0 - exp(-dt / tau))


func _render_span(at: int, n: int) -> void:
	var dt: float = float(n) / RATE
	# smoothed controls, once per span (as Web Audio's setTargetAtTime ramps)
	if _pad_gain_wait > 0.0:
		_pad_gain_wait -= dt
	else:
		_pad_gain = _approach(_pad_gain, _pad_gain_target, _pad_gain_tau, dt)
	_cut = _approach(_cut, _cut_target, _cut_tau, dt)
	_lfo_f = _approach(_lfo_f, _lfo_target, _lfo_tau, dt)
	_sub_f = _approach(_sub_f, _sub_target, _sub_tau, dt)
	_sub_g = _approach(_sub_g, _sub_target_g, 2.0, dt)
	_groove_g = _approach(_groove_g, _groove_target, _groove_tau, dt)
	_delay_len = _approach(_delay_len, _delay_len_target, 0.5, dt)
	_out_gain = _approach(_out_gain, _out_target, 0.3, dt)
	for i in n:
		_mix[at + i] = 0.0
		_echo_in[at + i] = 0.0
		_pad_mix[at + i] = 0.0
	# the pad: five resampled loops, gains ramping, pitches gliding
	var keep_pads: Array = []
	for v in _pads:
		if v["dying"] and _pos >= int(v["die_at"]):
			continue
		keep_pads.append(v)
		v["f"] = _approach(float(v["f"]), float(v["f_target"]), float(v["tau"]), dt)
		v["g"] = _approach(float(v["g"]), float(v["g_target"]), float(v["g_tau"]), dt)
		var g: float = v["g"]
		if g < 0.0005:
			continue
		var loop: PackedFloat32Array = v["loop"]
		var L := loop.size()
		var ph: float = v["ph"]
		var inc: float = float(v["f"]) / PAD_REF
		for i in n:
			var ip := int(ph)
			var fr: float = ph - ip
			var s0: float = loop[ip]
			var s1: float = loop[(ip + 1) % L]
			_pad_mix[at + i] += (s0 + (s1 - s0) * fr) * g
			ph += inc
			if ph >= L:
				ph -= L
		v["ph"] = ph
	_pads = keep_pads
	# the breathing lowpass over the pad, then the pad gain into the mix
	var co := _biquad("lowpass", _cut + 260.0 * sin(_lfo_ph * TAU), 0.8)
	_lfo_ph = fmod(_lfo_ph + _lfo_f * dt, 1.0)
	for i in n:
		var x: float = _pad_mix[at + i]
		var y: float = co[0] * x + co[1] * _fx1 + co[2] * _fx2 - co[3] * _fy1 - co[4] * _fy2
		_fx2 = _fx1
		_fx1 = x
		_fy2 = _fy1
		_fy1 = y
		_mix[at + i] += y * _pad_gain
	# the sub
	if _sub_g > 0.0005:
		var tbl: PackedFloat32Array = _tables[_sub_wave]
		var inc: float = _sub_f / RATE
		for i in n:
			_mix[at + i] += tbl[int(_sub_ph * TABLE) % TABLE] * _sub_g
			_sub_ph += inc
			if _sub_ph >= 1.0:
				_sub_ph -= 1.0
	# the one-shots
	var keep: Array = []
	var gg := _groove_g
	for v in _voices:
		var alive := true
		var gv: float = gg if v["groove"] else 1.0
		var to_echo: bool = v["echo"]
		match v["kind"]:
			"sample":
				var buf: PackedFloat32Array = v["buf"]
				var idx: int = v["i"]
				var vol: float = float(v["vol"]) * gv
				for i in n:
					if idx >= 0 and idx < buf.size():
						var s: float = buf[idx] * vol
						if to_echo:
							_echo_in[at + i] += s
						else:
							_mix[at + i] += s
					idx += 1
				v["i"] = idx
				alive = idx < buf.size()
			"note":
				var tbl: PackedFloat32Array = v["tbl"]
				var ph: float = v["ph"]
				var inc: float = float(v["f"]) / RATE
				var a: float = v["a"]
				var d: float = v["d"]
				var peak: float = float(v["vol"]) * gv
				var age: float = v["age"]
				var decay: float = pow(0.0001 / max(peak, 0.0002), 1.0 / max(1.0, d * RATE))
				for i in n:
					var e: float
					if age < a:
						e = 0.0001 + (peak - 0.0001) * (age / a)
					else:
						e = peak * pow(decay, (age - a) * RATE)
					var s: float = tbl[int(ph * TABLE) % TABLE] * e
					if to_echo:
						_echo_in[at + i] += s
					else:
						_mix[at + i] += s
					ph += inc
					if ph >= 1.0:
						ph -= 1.0
					age += 1.0 / RATE
				v["ph"] = ph
				v["age"] = age
				alive = age < a + d
			"bass":
				var tbl: PackedFloat32Array = v["tbl"]
				var ph: float = v["ph"]
				var inc: float = float(v["f"]) / RATE
				var a: float = v["a"]
				var d: float = v["d"]
				var peak: float = float(v["vol"]) * gv
				var age: float = v["age"]
				var sine: bool = v["sine"]
				var cutoff: float = 600.0 if sine else 900.0 * pow(160.0 / 900.0, min(1.0, age / 0.2))
				var bco := _biquad("lowpass", cutoff, 0.5 if sine else 3.0)
				var x1: float = v["x1"]
				var x2: float = v["x2"]
				var y1: float = v["y1"]
				var y2: float = v["y2"]
				var decay: float = pow(0.0001 / max(peak, 0.0002), 1.0 / max(1.0, d * RATE))
				for i in n:
					var e: float
					if age < a:
						e = 0.0001 + (peak - 0.0001) * (age / a)
					else:
						e = peak * pow(decay, (age - a) * RATE)
					var x: float = tbl[int(ph * TABLE) % TABLE]
					var y: float = bco[0] * x + bco[1] * x1 + bco[2] * x2 - bco[3] * y1 - bco[4] * y2
					x2 = x1
					x1 = x
					y2 = y1
					y1 = y
					_mix[at + i] += y * e
					ph += inc
					if ph >= 1.0:
						ph -= 1.0
					age += 1.0 / RATE
				v["ph"] = ph
				v["age"] = age
				v["x1"] = x1
				v["x2"] = x2
				v["y1"] = y1
				v["y2"] = y2
				alive = age < 0.7
		if alive:
			keep.append(v)
	_voices = keep
	if _voices.size() > voices_peak:
		voices_peak = _voices.size()
	# the echo: darkened and fed back, its time following the tempo; wet into the mix
	var dl: int = clampi(int(_delay_len * RATE), 1, _delay.size() - 1)
	for i in n:
		var rd: int = (_delay_pos - dl + _delay.size()) % _delay.size()
		var back: float = _delay[rd]
		_delay_lp += (back - _delay_lp) * 0.5   # a one-pole lowpass round 2.4 kHz at this rate
		_delay[_delay_pos] = _echo_in[at + i] + _delay_lp * 0.42
		_mix[at + i] += back * 0.45
		_delay_pos = (_delay_pos + 1) % _delay.size()
	# out
	for i in n:
		_mix[at + i] = clampf(_mix[at + i] * _out_gain, -1.0, 1.0)
