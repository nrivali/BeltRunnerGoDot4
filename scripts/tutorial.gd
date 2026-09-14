class_name Tutorial
extends Node
## The Flight Ops questline, ported from TUT in belt-runner-3d.html: fourteen steps that walk a new pilot through the
## launch, the controls, the HUD, the radar, cutting a copper rock, the hold, docking, the pad, stowing, refits, the Hub
## and the departure. Every step is spoken by a recorded line (sfx/tut_<id>.mp3) when it appears, and again from the
## card's Replay button. Steps with `auto` wait for the pilot to actually do the thing; the rest wait for Next (Enter).
## Progress is State.tut (-1 once finished or skipped).

const STEPS := [
	{"id": "launch", "title": "Welcome aboard", "text": "Flight Ops is on the line. Press W on the pad and approach control taxis you out of the hangar; the ship is yours the moment it lets go.", "wait": "press W to launch"},
	{"id": "steer", "title": "Take the stick", "ring": "controls", "wait": "open the throttle and turn", "text": "The mouse steers. W and S work the throttle, A and D roll, X cuts the throttle. Open her up and give me a turn."},
	{"id": "hud", "title": "Ship and world", "ring": "status", "ring2": "readout", "text": "Bottom centre is your ship: hull, fuel, speed, thrust and cargo. Top right is the world: zone, laser, radar, and whatever you are looking at."},
	{"id": "radar", "title": "Find ore", "ring": "readout", "wait": "press R", "text": "Press R to pulse the radar. Every rock it reaches is marked for a while. Ore shows as coloured veins and crystals; plain grey rock is barren, so do not waste the laser on it."},
	{"id": "lock", "title": "Lock a copper rock", "ring": "target", "wait": "press Q on a copper rock", "text": "Find a copper rock (orange veins), put the mouse on it and press Q to lock it. The target panel shows its size and what is left in it."},
	{"id": "mine", "title": "Cut it", "ring": "target", "wait": "collect copper", "text": "Get within laser reach and hold the left mouse button (Space or L too). The dish under the nose cuts while you hold. When the rock breaks, fly through the glow and the ore comes aboard."},
	{"id": "inv", "title": "Your hold", "wait": "press Tab", "text": "Copper in the hold. Press Tab for your inventory: four slots, one stack each. Deposit all moves it aboard the cargo ship once you are docked."},
	{"id": "return", "title": "Head home", "ring": "marker", "wait": "dock with the cargo ship", "text": "Follow the CARGO SHIP marker. Within 2,250 press E and approach control brings you in, or fly slowly into either hangar mouth yourself."},
	{"id": "hangar", "title": "On the pad", "ring": "status", "text": "Your tank fills from the cargo ship's fuel supply and your hull mends from its repair parts, one part per hull point. Both run down, and both restock at the Hub."},
	{"id": "stow", "title": "Stow the haul", "ring": "deposit", "wait": "move copper into storage", "text": "Press E, or Deposit all, to move your copper into the cargo ship's storage: 50 slots, and it all warps with you. Your hold is for the trip out; the storage is for the haul."},
	{"id": "refit", "title": "Refits", "ring": "refits", "text": "The services panel lists your refits: laser, engine, tank, cargo, scanner, hull. A bigger hold and a stronger laser pay for themselves fastest. The cargo ship's own upgrades sit below them."},
	{"id": "hub", "title": "Selling", "ring": "navmap", "text": "Nothing sells out here. Press N for the nav map and warp to the Hub. Meridian Colony buys everything, and it is where the cargo ship refuels and restocks."},
	{"id": "depart", "title": "Back out", "ring": "depart", "wait": "press Depart", "text": "Press Depart (or W on the pad) to launch. The belt is all yours out there: fill the hold and bring it home. Keep an eye on the fuel; the pad tops you up every time you dock."},
	{"id": "done", "title": "Tutorial complete", "final": true, "text": "That is the loop: fill the hold, stow it, warp to the Hub, sell, refit, repeat. Flight Ops out. Good hunting."},
]

var main
var ship: Ship
var hud: Hud
var flags := {"pulsed": false, "flown": false, "head0": null}
var _shown := -1


func active() -> bool:
	return State.tut >= 0


func step() -> int:
	return State.tut


func _auto(s: Dictionary) -> bool:
	match s["id"]:
		"launch": return not ship.docked and ship.cut.is_empty()
		"steer": return flags["flown"]
		"radar": return ship.radar_pulsed
		"lock": return ship.lock_kind == "rock" and main.belt.ore[ship.lock_rock] >= 0 and Data.ORE_KEYS[main.belt.ore[ship.lock_rock]] == "copper"
		"mine": return State.cargo["copper"] >= 1.0
		"inv": return hud.inv_open
		"return": return ship.docked
		"stow": return State.store["copper"] >= 1.0
		"depart": return not ship.docked and ship.cut.is_empty()
	return false


func _is_auto(s: Dictionary) -> bool:
	return s.has("wait") and not s.get("final", false)


func update(dt: float) -> void:
	if not active():
		if _shown != -1:
			_shown = -1
			hud.show_tutorial({})
		return
	var i := step()
	var s: Dictionary = STEPS[i]
	if _shown != i:
		_shown = i
		hud.show_tutorial({"step": i + 1, "total": STEPS.size(), "title": s["title"], "text": s["text"], "auto": _is_auto(s), "wait": s.get("wait", ""), "final": s.get("final", false), "ring": s.get("ring", ""), "ring2": s.get("ring2", "")})
		speak()
	# the steering step wants a real turn under power: the heading has to swing 60 degrees from where the step began while moving
	if s["id"] == "steer" and not flags["flown"]:
		var f := ship.forward()
		if flags["head0"] == null:
			flags["head0"] = f
		elif ship.speed() > 150.0 and f.dot(flags["head0"]) < 0.5:
			flags["flown"] = true
	# the card stands aside for cutscenes and the map (the departure taxi is not a cutscene: the launch line plays over it)
	hud.tutorial_hidden(ship.in_cinematic() or hud.map_open)
	if _is_auto(s) and _auto(s):
		advance()
	if Input.is_action_just_pressed("tut_next") and not _is_auto(s):
		advance()


func speak() -> void:
	if active():
		Audio.voice("tut_" + STEPS[step()]["id"])


func advance() -> void:
	if not active():
		return
	var s: Dictionary = STEPS[step()]
	if s.get("final", false):
		State.tut = -1
		Audio.stop_voice()
		Audio.sfx("chime")
		hud.toast("Tutorial complete", false)
		State.save_game()
		return
	State.tut += 1
	flags["pulsed"] = false
	flags["flown"] = false
	flags["head0"] = null
	ship.radar_pulsed = false
	State.save_game()


func skip() -> void:
	State.tut = -1
	Audio.stop_voice()
	hud.toast("Tutorial skipped", false)
	State.save_game()


func restart() -> void:
	State.tut = 0
	_shown = -1
	flags["pulsed"] = false
	flags["flown"] = false
	flags["head0"] = null
	State.save_game()
