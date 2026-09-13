extends Node
## Recorded audio, ported from the browser game's SFX module: every clip is an mp3 under res://sfx (the ElevenLabs
## recordings). Voice lines are radio transmissions: the key clicks open with a burst of static (radio_on), the line
## follows a beat later, and the squelch closes it when it ends or is cut off by the next one; one voice at a time. The
## hangar deck's announcements go through the intercom bus instead: a tannoy band-pass, a little overdrive and the
## reverb of a big steel room, with the PA chime before each. One-shots (dock, chime, cash, stow, pickup, rock_break)
## play from a small pool. Missing clips are simply silent.

const RADIO_LEAD := 0.32
const PA_LEAD := 1.1
const GAIN := {"radio_on": -6.0, "radio_off": -7.0, "pa_chime": -6.0, "dock": -3.0, "chime": -6.0, "cash": -4.0, "stow": -4.0, "pickup": -7.0, "rock_break": -3.0, "hit": -3.0, "laser_on": -6.0, "laser_off": -8.0, "laser_bite": -7.0, "radar_ping": -6.0}

## The continuous layers, ported from the SFX module's loops: an idle hum under a thrust roar that rises in pitch with
## the throttle, a boost roar on top, retro hiss while braking; a throbbing beam while the laser fires with a sizzling
## cut layered on when it is on a rock; and the quiet space hum that is always there. Each runs on its own player at
## gain zero and is faded toward a target every frame.
const LOOP_NAMES := ["engine_idle", "engine_thrust", "engine_boost", "retro", "laser_beam", "laser_cut", "space_hum"]
var _loops := {}       # name -> {player, gain, target, tau}
var _laser_on := false
var _laser_cutting := false

var _streams := {}
var _voice: AudioStreamPlayer
var _voice_radio := false
var _pool: Array = []
var _pa: AudioStreamPlayer
var _squelch: AudioStreamPlayer
var plays := {}   # name -> times played (for the smoke test)


func _ready() -> void:
	_setup_intercom_bus()
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Master"
	add_child(_voice)
	_voice.finished.connect(_on_voice_finished)
	_pa = AudioStreamPlayer.new()
	_pa.bus = "Intercom"
	add_child(_pa)
	_squelch = AudioStreamPlayer.new()
	add_child(_squelch)
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_start_loops()


func _start_loops() -> void:
	for nm in LOOP_NAMES:
		var s := stream(nm)
		if s == null:
			continue
		if s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_loops[nm] = {"player": p, "gain": 0.0, "target": 0.07 if nm == "space_hum" else 0.0, "tau": 0.5}


func _loop_target(name: String, g: float, tau: float) -> void:
	if _loops.has(name):
		_loops[name]["target"] = g
		_loops[name]["tau"] = tau


func _process(dt: float) -> void:
	for nm in _loops:
		var l: Dictionary = _loops[nm]
		var g: float = l["gain"]
		var t: float = l["target"]
		g += (t - g) * (1.0 - exp(-dt / max(0.02, float(l["tau"]))))
		l["gain"] = g
		var p: AudioStreamPlayer = l["player"]
		p.volume_db = linear_to_db(g) if g > 0.001 else -80.0


## The engine mix for this frame (the HTML's SFX.engine): throttle 0..1, afterburner on, retros firing, or parked/idle.
func engine(throttle: float, boost: bool, braking: bool, idle: bool) -> void:
	var th := 0.0 if idle else throttle
	_loop_target("engine_idle", 0.05 if idle else 0.14, 0.2)
	_loop_target("engine_thrust", th * 0.5, 0.15)
	_loop_target("engine_boost", 0.55 if (boost and not idle) else 0.0, 0.2)
	_loop_target("retro", 0.3 if braking else 0.0, 0.06)
	if _loops.has("engine_thrust"):
		var p: AudioStreamPlayer = _loops["engine_thrust"]["player"]
		p.pitch_scale = lerp(p.pitch_scale, 0.85 + th * 0.3, 0.1)


## The laser mix (the HTML's SFX.laser): the beam loop while firing, the cut loop on a rock, and the on/off/bite transients.
func laser(firing: bool, cutting: bool) -> void:
	if firing and not _laser_on:
		sfx("laser_on")
	if not firing and _laser_on:
		sfx("laser_off")
	if cutting and not _laser_cutting:
		sfx("laser_bite")
	_laser_on = firing
	_laser_cutting = cutting
	_loop_target("laser_beam", (0.16 if cutting else 0.26) if firing else 0.0, 0.12 if firing else 0.06)
	_loop_target("laser_cut", 0.32 if cutting else 0.0, 0.1)


## Current loop gains, for the smoke test.
func loop_state() -> Dictionary:
	var out := {}
	for nm in _loops:
		out[nm] = snappedf(_loops[nm]["gain"], 0.001)
	return out


func _setup_intercom_bus() -> void:
	if AudioServer.get_bus_index("Intercom") >= 0:
		return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Intercom")
	AudioServer.set_bus_send(idx, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 380.0
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3800.0
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(3, 5.0)   # the honk of a horn speaker around 2 kHz
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	drive.drive = 0.22
	drive.pre_gain = 4.0
	var rev := AudioEffectReverb.new()
	rev.room_size = 0.85
	rev.damping = 0.4
	rev.predelay_msec = 28.0
	rev.wet = 0.45
	rev.dry = 0.62
	for e in [hp, eq, lp, drive, rev]:
		AudioServer.add_bus_effect(idx, e)


func stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var s = load("res://sfx/%s.mp3" % name)
	_streams[name] = s
	return s


func _count(name: String) -> void:
	plays[name] = plays.get(name, 0) + 1


## A one-shot from the pool.
func sfx(name: String, extra_db := 0.0) -> void:
	var s := stream(name)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.volume_db = GAIN.get(name, -5.0) + extra_db
			p.play()
			_count(name)
			return


## A radio call: squelch open, the line a beat later, squelch closed when it ends. Cuts off any line already playing.
func voice(name: String) -> void:
	var s := stream(name)
	if s == null:
		return
	stop_voice()
	_voice_radio = true
	_squelch_play("radio_on")
	_voice.stream = s
	_voice.volume_db = -2.0
	var tok := _voice
	get_tree().create_timer(RADIO_LEAD).timeout.connect(func():
		if _voice == tok and _voice_radio and not _voice.playing and _voice.stream == s:
			_voice.play()
			_count(name))


## A deck announcement over the intercom: the PA chime, then the line through the tannoy chain, no squelch.
func intercom(name: String) -> void:
	var s := stream(name)
	if s == null:
		return
	stop_voice()
	_voice_radio = false
	_pa.stream = stream("pa_chime")
	if _pa.stream:
		_pa.volume_db = GAIN["pa_chime"]
		_pa.play()
	get_tree().create_timer(PA_LEAD).timeout.connect(func():
		if not _voice_radio and not _voice.playing:
			_voice.bus = "Intercom"
			_voice.stream = s
			_voice.volume_db = 2.0
			_voice.play()
			_count(name))


func stop_voice() -> void:
	if _voice.playing:
		_voice.stop()
		if _voice_radio:
			_squelch_play("radio_off")
	_voice.stream = null
	_voice.bus = "Master"


func _on_voice_finished() -> void:
	if _voice_radio:
		_squelch_play("radio_off")
	_voice.bus = "Master"


func _squelch_play(name: String) -> void:
	var s := stream(name)
	if s == null:
		return
	_squelch.stream = s
	_squelch.volume_db = GAIN.get(name, -6.0)
	_squelch.play()
	_count(name)
