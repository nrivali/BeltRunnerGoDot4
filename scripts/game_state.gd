extends Node
## The pilot's persistent state: credits, hold, fuel, hull and refit levels. Ported from `state` in belt-runner-3d.html.
## Saved as JSON under user:// (Godot's per-user data folder) with the same field names as the browser save, so a
## future importer can read the localStorage save straight in.

const SAVE_PATH := "user://belt-runner-save.json"

var credits := 60.0
var cargo := {}        # ore key -> units in the hold
var fuel := 100.0
var hull := 100.0
var up := {"laser": 0, "cargo": 0, "engine": 0, "tank": 0, "scanner": 0, "range": 0, "hull": 0, "thrusters": 0, "overcharge": 0}
var mined := 0.0
var earned := 0.0
var time := 0.0


func _ready() -> void:
	for k in Data.ORE_KEYS:
		if not cargo.has(k):
			cargo[k] = 0.0
	load_game()


## The level entry of a refit, e.g. stat("engine").max
func stat(key: String) -> Dictionary:
	return Data.UPGRADES[key]["levels"][up[key]]


func cargo_slots() -> int:
	return int(stat("cargo")["slots"])


func cargo_total() -> float:
	var t := 0.0
	for k in cargo:
		t += cargo[k]
	return t


func cargo_capacity() -> float:
	return cargo_slots() * Data.STACK


## Units of ore that fit: stacks are per ore, one slot per STACK units, and the hold has cargo_slots() slots.
func cargo_room(ore: String) -> float:
	var used_slots := 0
	for k in cargo:
		if k != ore and cargo[k] > 0.5:
			used_slots += int(ceil(cargo[k] / Data.STACK))
	var have: float = cargo[ore]
	var slots_for_ore := cargo_slots() - used_slots
	return max(0.0, slots_for_ore * Data.STACK - have)


func add_cargo(ore: String, units: float) -> float:
	var room := cargo_room(ore)
	var took: float = min(units, room)
	cargo[ore] += took
	mined += took
	return took


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"credits": credits, "cargo": cargo, "fuel": fuel, "hull": hull, "up": up, "mined": mined, "earned": earned, "time": time}))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var s = JSON.parse_string(f.get_as_text())
	if typeof(s) != TYPE_DICTIONARY:
		return false
	credits = float(s.get("credits", credits))
	fuel = float(s.get("fuel", fuel))
	hull = float(s.get("hull", hull))
	mined = float(s.get("mined", mined))
	earned = float(s.get("earned", earned))
	time = float(s.get("time", time))
	var c = s.get("cargo", {})
	for k in Data.ORE_KEYS:
		cargo[k] = float(c.get(k, 0.0))
	var u = s.get("up", {})
	for k in up:
		up[k] = clampi(int(u.get(k, 0)), 0, Data.UPGRADES[k]["levels"].size() - 1)
	return true
