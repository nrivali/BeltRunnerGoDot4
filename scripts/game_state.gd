extends Node
## The pilot's persistent state: credits, hold, fuel, hull and refit levels, plus the cargo ship's storage, fuel supply
## and repair parts. Ported from `state` in belt-runner-3d.html. Saved as JSON under user:// with the browser save's
## field names, so a future importer can read the localStorage save straight in.

const SAVE_PATH := "user://belt-runner-save.json"

var credits := 60.0
var cargo := {}        # ore key -> units in the hold
var store := {}        # ore key -> units in the cargo ship's storage (50 slots)
var fuel := 100.0
var hull := 100.0
var up := {"laser": 0, "cargo": 0, "engine": 0, "tank": 0, "scanner": 0, "range": 0, "hull": 0, "thrusters": 0, "overcharge": 0}
var depot := {"laser": 0, "collectors": 0}   # cargo ship upgrades (not active in the port yet; kept so saves round-trip)
var ship_fuel := 1200.0   # the cargo ship's fuel supply, which the ship's tank fills from while docked
var parts := 120.0        # repair parts aboard the cargo ship, one per hull point mended while docked
var mined := 0.0
var earned := 0.0
var time := 0.0


func _ready() -> void:
	for k in Data.ORE_KEYS:
		if not cargo.has(k):
			cargo[k] = 0.0
		if not store.has(k):
			store[k] = 0.0
	load_game()


## The level entry of a refit, e.g. stat("engine").max
func stat(key: String) -> Dictionary:
	return Data.UPGRADES[key]["levels"][up[key]]


# ---- the hold: slots of STACK units, one ore per slot
func cargo_slots() -> int:
	return int(stat("cargo")["slots"])


static func _stacks(units: float) -> int:
	return int(ceil(units / Data.STACK - 1e-6))


func used_slots() -> int:
	var n := 0
	for k in cargo:
		n += _stacks(cargo[k])
	return n


func free_slots() -> int:
	return max(0, cargo_slots() - used_slots())


func cargo_total() -> float:
	var t := 0.0
	for k in cargo:
		t += cargo[k]
	return t


func cargo_capacity() -> float:
	return cargo_slots() * Data.STACK


## Units of ore `ore` that still fit: the part-filled stack tops up first, then empty slots.
func cargo_room(ore: String) -> float:
	var have: float = cargo[ore]
	return (_stacks(have) * Data.STACK - have) + free_slots() * Data.STACK


func add_cargo(ore: String, units: float) -> float:
	var took: float = min(units, cargo_room(ore))
	cargo[ore] += took
	mined += took
	return took


# ---- the cargo ship's storage: the same slot rules, 50 slots
func store_used() -> int:
	var n := 0
	for k in store:
		n += _stacks(store[k])
	return n


func store_free() -> int:
	return max(0, Data.STORE_SLOTS - store_used())


func store_room(ore: String) -> float:
	var have: float = store[ore]
	return (_stacks(have) * Data.STACK - have) + store_free() * Data.STACK


func store_total() -> float:
	var t := 0.0
	for k in store:
		t += store[k]
	return t


## Everything in the hold into the storage. Returns the units moved.
func stow_all() -> float:
	var moved := 0.0
	for k in Data.ORE_KEYS:
		var u: float = min(cargo[k], store_room(k))
		if u > 0.01:
			cargo[k] -= u
			store[k] += u
			moved += u
			if cargo[k] < 0.01:
				cargo[k] = 0.0
	return moved


## Everything in the storage back into the hold, as far as it fits. Returns the units moved.
func take_all() -> float:
	var moved := 0.0
	for k in Data.ORE_KEYS:
		var u: float = min(store[k], cargo_room(k))
		if u > 0.01:
			store[k] -= u
			cargo[k] += u
			moved += u
			if store[k] < 0.01:
				store[k] = 0.0
	return moved


## The value of a hold or storage dictionary at Hub prices (no market drift in the port yet).
static func value_of(bag: Dictionary) -> float:
	var v := 0.0
	for k in bag:
		var o: Dictionary = Data.ORES[k]
		v += bag[k] * o["price"] * (Data.EXPORT_BONUS if o.has("zone") else 1.0)
	return v


# ---- refits
## Buy the next level of a refit. Returns a message for the toast, and whether it went through.
func buy(key: String) -> Dictionary:
	var u: Dictionary = Data.UPGRADES[key]
	var i: int = up[key]
	if i >= u["costs"].size():
		return {"ok": false, "msg": "%s is fully upgraded" % u["name"]}
	var c: float = u["costs"][i]
	if credits < c:
		return {"ok": false, "msg": "Not enough credits"}
	credits -= c
	up[key] = i + 1
	if key == "hull":
		hull = float(stat("hull")["hp"])   # new plating goes on whole
	save_game()
	return {"ok": true, "msg": "%s refit to Lv%d" % [u["name"], i + 2]}


func save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"credits": credits, "cargo": cargo, "store": store, "fuel": fuel, "hull": hull, "up": up, "depot": depot, "shipFuel": ship_fuel, "parts": parts, "mined": mined, "earned": earned, "time": time}))


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
	ship_fuel = min(Data.CARGO_FUEL_CAP, float(s.get("shipFuel", ship_fuel)))
	parts = min(float(Data.PARTS_CAP), float(s.get("parts", parts)))
	mined = float(s.get("mined", mined))
	earned = float(s.get("earned", earned))
	time = float(s.get("time", time))
	var c = s.get("cargo", {})
	var st = s.get("store", {})
	for k in Data.ORE_KEYS:
		cargo[k] = float(c.get(k, 0.0))
		store[k] = float(st.get(k, 0.0))
	var u = s.get("up", {})
	for k in up:
		up[k] = clampi(int(u.get(k, 0)), 0, Data.UPGRADES[k]["levels"].size() - 1)
	var d = s.get("depot", {})
	for k in depot:
		depot[k] = int(d.get(k, 0))
	return true
