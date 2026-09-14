extends Node
## The pilot's persistent state: credits, hold, fuel, hull and refit levels, the cargo ship's storage, fuel supply and
## repair parts, the colony market and which zone you are in. Ported from `state` in belt-runner-3d.html. Saved as
## JSON under user:// with the browser save's field names, so a future importer can read the localStorage save in.

const SAVE_PATH := "user://belt-runner-save.json"

var credits := 60.0
var cargo := {}        # ore key -> units in the hold
var store := {}        # ore key -> units in the cargo ship's storage (50 slots)
var fuel := 100.0
var hull := 100.0
var up := {"laser": 0, "cargo": 0, "engine": 0, "tank": 0, "scanner": 0, "range": 0, "hull": 0, "thrusters": 0, "overcharge": 0}
var depot := {"laser": 0, "collectors": 0}   # cargo ship upgrades: the mast dish and the collector drones
var drone_units := 0.0                       # ore the collectors have stowed, all told
var ship_fuel := 1200.0   # the cargo ship's fuel supply, which the ship's tank fills from while docked
var parts := 120.0        # repair parts aboard the cargo ship, one per hull point mended while docked
var market := {}          # ore key -> price multiplier, drifting toward market_next every MARKET_PERIOD seconds
var market_next := {}
var market_t := 0.0
var zone_id := "kessler"
var tut := 0              # tutorial step; -1 once finished or skipped
var mined := 0.0
var earned := 0.0
var time := 0.0
var settings := {"sound": true, "volume": 1.0, "music": true, "music_volume": 1.0, "hud": 1.0, "controls": true}   # the menu's settings, saved with the game
var has_save := false


func _ready() -> void:
	for k in Data.ORE_KEYS:
		if not cargo.has(k):
			cargo[k] = 0.0
		if not store.has(k):
			store[k] = 0.0
		market[k] = 1.0
		market_next[k] = 1.0
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


# ---- the market (the Hub's colony is the only one): prices drift, exports carry the premium
func price(k: String) -> float:
	var o: Dictionary = Data.ORES[k]
	return o["price"] * float(market[k]) * (Data.EXPORT_BONUS if o.has("zone") else 1.0)


## The value of a hold or storage dictionary at today's prices.
func value_of(bag: Dictionary) -> float:
	var v := 0.0
	for k in bag:
		v += bag[k] * price(k)
	return v


func tick_market(dt: float) -> void:
	market_t -= dt
	if market_t <= 0.0:
		market_t = Data.MARKET_PERIOD
		for k in Data.ORE_KEYS:
			market_next[k] = randf_range(0.8, 1.25)
	for k in Data.ORE_KEYS:
		market[k] += (market_next[k] - market[k]) * min(1.0, dt * 0.08)


## Sell the given ores from the hold and/or the storage. Returns {units, credits}.
func sell(keys: Array, from_hold: bool, from_store: bool) -> Dictionary:
	var cr := 0.0
	var units := 0.0
	for k in keys:
		var u := 0.0
		if from_hold:
			u += cargo[k]
			cargo[k] = 0.0
		if from_store:
			u += store[k]
			store[k] = 0.0
		if u > 0.01:
			cr += u * price(k)
			units += u
	if units >= 0.5:
		credits += cr
		earned += cr
		save_game()
	return {"units": units, "credits": cr}


## Fill the cargo ship's fuel supply at the colony, as far as credits go. Returns {units, cost, partial}.
func refuel_cargo_ship() -> Dictionary:
	var want := Data.CARGO_FUEL_CAP - ship_fuel
	var u: float = min(want, credits / Data.CARGO_FUEL_PRICE)
	if want < 0.5:
		return {"units": 0.0, "cost": 0.0, "partial": false, "msg": "Fuel supply is already full"}
	if u < 1.0:
		return {"units": 0.0, "cost": 0.0, "partial": false, "msg": "Not enough credits for fuel"}
	ship_fuel += u
	credits = max(0.0, credits - u * Data.CARGO_FUEL_PRICE)
	save_game()
	return {"units": u, "cost": u * Data.CARGO_FUEL_PRICE, "partial": u < want - 0.5, "msg": ""}


func buy_parts() -> Dictionary:
	var want := float(Data.PARTS_CAP) - parts
	var n: float = min(want, floor(credits / Data.PARTS_PRICE))
	if want < 0.5:
		return {"units": 0.0, "cost": 0.0, "partial": false, "msg": "Repair parts store is already full"}
	if n < 1.0:
		return {"units": 0.0, "cost": 0.0, "partial": false, "msg": "Not enough credits for repair parts"}
	parts += n
	credits -= n * Data.PARTS_PRICE
	save_game()
	return {"units": n, "cost": n * Data.PARTS_PRICE, "partial": n < want - 0.5, "msg": ""}


## Storage room for any ore at all (a drone only goes out if there is somewhere to put what it brings back).
func store_any_room() -> bool:
	if store_free() > 0:
		return true
	for k in store:
		if store[k] > 0.5 and _stacks(store[k]) * Data.STACK - store[k] > 0.5:
			return true
	return false


## Buy the next level of a cargo ship upgrade.
func buy_depot(key: String) -> Dictionary:
	var u: Dictionary = Data.DEPOT_UPGRADES[key]
	var i: int = depot[key]
	if i >= u["costs"].size():
		return {"ok": false, "msg": "%s is fully upgraded" % u["name"]}
	var c: float = u["costs"][i]
	if credits < c:
		return {"ok": false, "msg": "Not enough credits"}
	credits -= c
	depot[key] = i + 1
	save_game()
	return {"ok": true, "msg": "%s %s" % [u["name"], "installed" if i == 0 else "upgraded to Lv%d" % (i + 1)]}


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
	f.store_string(JSON.stringify({"credits": credits, "cargo": cargo, "store": store, "fuel": fuel, "hull": hull, "up": up, "depot": depot, "droneUnits": drone_units, "shipFuel": ship_fuel, "parts": parts, "market": market, "zone": zone_id, "tut": tut, "mined": mined, "earned": earned, "time": time, "settings": settings}))
	has_save = true


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
	zone_id = str(s.get("zone", zone_id))
	tut = int(s.get("tut", -1))   # saves from before the tutorial existed skip it
	var c = s.get("cargo", {})
	var st = s.get("store", {})
	var mk = s.get("market", {})
	for k in Data.ORE_KEYS:
		cargo[k] = float(c.get(k, 0.0))
		store[k] = float(st.get(k, 0.0))
		market[k] = float(mk.get(k, 1.0))
		market_next[k] = market[k]
	var u = s.get("up", {})
	for k in up:
		up[k] = clampi(int(u.get(k, 0)), 0, Data.UPGRADES[k]["levels"].size() - 1)
	var d = s.get("depot", {})
	for k in depot:
		depot[k] = clampi(int(d.get(k, 0)), 0, Data.DEPOT_UPGRADES[k]["costs"].size())
	drone_units = float(s.get("droneUnits", 0.0))
	var sg = s.get("settings", {})
	if typeof(sg) == TYPE_DICTIONARY:
		for k in settings:
			if sg.has(k):
				settings[k] = sg[k]
	has_save = true
	return true


## A fresh pilot: the browser's resetSave. The settings survive; the save file goes.
func reset() -> void:
	credits = 60.0
	fuel = 100.0
	hull = 100.0
	for k in Data.ORE_KEYS:
		cargo[k] = 0.0
		store[k] = 0.0
		market[k] = 1.0
		market_next[k] = 1.0
	for k in up:
		up[k] = 0
	for k in depot:
		depot[k] = 0
	drone_units = 0.0
	ship_fuel = 1200.0
	parts = 120.0
	market_t = 0.0
	zone_id = "kessler"
	tut = 0
	mined = 0.0
	earned = 0.0
	time = 0.0
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	has_save = false


# ---- stacks: the inventory grid's view of a bag (hold or storage), most valuable ore first, full stacks then the rest
func stacks(bag: Dictionary) -> Array:
	var keys: Array = []
	for k in Data.ORE_KEYS:
		if bag[k] > 0.5:
			keys.append(k)
	keys.sort_custom(func(a, b): return price(a) > price(b))
	var out: Array = []
	for k in keys:
		var left: float = bag[k]
		while left > 0.5:
			var u: float = min(Data.STACK, left)
			out.append({"k": k, "u": u})
			left -= u
	return out


## Drop one stack of `k` (up to `units`) into space. Returns the units dropped.
func jettison(k: String, units: float) -> float:
	var u: float = min(units, cargo[k])
	cargo[k] -= u
	if cargo[k] < 0.01:
		cargo[k] = 0.0
	save_game()
	return u


## One stack of `k` from the hold into the storage, as far as it fits. Returns the units moved.
func stow_stack(k: String, units: float) -> float:
	var u: float = min(units, cargo[k], store_room(k))
	if u < 0.01:
		return 0.0
	cargo[k] -= u
	store[k] += u
	if cargo[k] < 0.01:
		cargo[k] = 0.0
	return u


## One stack of `k` from the storage back into the hold, as far as it fits. Returns the units moved.
func take_stack(k: String, units: float) -> float:
	var u: float = min(units, store[k], cargo_room(k))
	if u < 0.01:
		return 0.0
	store[k] -= u
	cargo[k] += u
	if store[k] < 0.01:
		store[k] = 0.0
	return u
