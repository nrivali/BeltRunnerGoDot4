extends Node
## Static game data, ported one for one from belt-runner-3d.html (v0.9.120). Distances are the browser game's world
## units, and a readout metre is half a unit (METRE), exactly as the HTML shows it, so every number here matches its
## JS constant. Only the Kessler Belt is live; the other zones stay in the HTML's SHELVED_ZONES until they are wanted.

const METRE := 0.5
const STACK := 100
const WORLD_SCALE := 100.0
const PLANET_SCALE := 250.0
const WORLD_EDGE_BASE := 11800.0
const GRAVITY_SURFACE := 55.0
const FUEL_BURN := 0.55
const OVER_BURN := 1.1
const SHIP_SCALE := 3.0
const SHIP_R := 16.0 * SHIP_SCALE
const PULSE_CD := 5.0
## The cargo ship: its orbit round the planet (inside the ring belt), fuel supply and repair-parts store, and 50-slot storage.
const DEPOT_ORBIT := 925000.0
const STATION_SPEED := 102.0
const CARGO_FUEL_CAP := 2500.0
const PARTS_CAP := 400
const STORE_SLOTS := 50
const DOCK_RANGE := 4500.0   # E within this of the carrier hands the ship to approach control (2,250 m on the readout)


## What a refit level gives, for the services panel (the HTML's describe()).
static func describe(key: String, i: int) -> String:
	var L: Dictionary = UPGRADES[key]["levels"][i]
	match key:
		"laser": return "%s dmg/s" % str(L["rate"])
		"cargo": return "%s slots" % str(L["slots"])
		"engine": return "%d thrust · %d top speed" % [roundi(L["thrust"] * METRE), roundi(L["max"] * METRE)]
		"thrusters": return ("×%s speed on Shift · ×%s fuel burn" % [str(L["mult"]), str(burn_mult(L["mult"]))]) if L["mult"] > 1 else "not fitted"
		"overcharge": return ("×%s laser damage · %.1f fuel/s while cutting" % [str(L["mult"]), OVER_BURN * L["mult"]]) if L["mult"] > 1.0 else "not fitted"
		"tank": return "%s fuel" % str(L["cap"])
		"scanner": return "%s m scan" % fm(L["range"])
		"range": return "%s m laser reach" % fm(L["reach"])
		"hull": return "%s hull points" % str(L["hp"])
	return ""

## Which laser level opens each ore: the five common ores in order, then the zone exclusives one level after the common
## ore of the same tier.
const ORES := {
	"iron":     {"name": "Iron",        "color": Color("#A3ABBC"), "price": 4,   "hardness": 1, "unlock": 2, "rarity": "Common"},
	"copper":   {"name": "Copper",      "color": Color("#D0834C"), "price": 9,   "hardness": 1, "unlock": 1, "rarity": "Uncommon"},
	"gold":     {"name": "Gold",        "color": Color("#F2C94C"), "price": 28,  "hardness": 2, "unlock": 3, "rarity": "Rare"},
	"platinum": {"name": "Platinum",    "color": Color("#35D6C2"), "price": 70,  "hardness": 3, "unlock": 4, "rarity": "Epic"},
	"crystal":  {"name": "Voidcrystal", "color": Color("#B98CFF"), "price": 160, "hardness": 4, "unlock": 5, "rarity": "Ultra rare"},
	"cobalt":   {"name": "Cobalt",      "color": Color("#3F7FE0"), "price": 16,  "hardness": 1, "unlock": 2, "rarity": "Exclusive", "zone": "kessler"},
	"beryl":    {"name": "Beryl",       "color": Color("#2FBF71"), "price": 45,  "hardness": 2, "unlock": 3, "rarity": "Exclusive", "zone": "kessler"},
}
const ORE_KEYS := ["iron", "copper", "gold", "platinum", "crystal", "cobalt", "beryl"]
const EXPORT_BONUS := 1.5

const UPGRADES := {
	"laser":      {"name": "Mining laser",     "levels": [{"rate": 3}, {"rate": 5}, {"rate": 8}, {"rate": 12}, {"rate": 18}], "costs": [350, 1400, 5000, 16000]},
	"cargo":      {"name": "Cargo hold",       "levels": [{"slots": 4}, {"slots": 6}, {"slots": 8}, {"slots": 11}, {"slots": 14}, {"slots": 18}], "costs": [200, 700, 2400, 7500, 20000]},
	"engine":     {"name": "Engines",          "levels": [{"thrust": 164, "max": 250}, {"thrust": 219, "max": 320}, {"thrust": 281, "max": 400}, {"thrust": 359, "max": 490}, {"thrust": 461, "max": 610}], "costs": [300, 1100, 3500, 10000]},
	"tank":       {"name": "Fuel tank",        "levels": [{"cap": 100}, {"cap": 160}, {"cap": 250}, {"cap": 400}, {"cap": 600}], "costs": [150, 600, 2000, 6000]},
	"scanner":    {"name": "Scanner",          "levels": [{"range": 28000}, {"range": 46000}, {"range": 74000}, {"range": 135000}], "costs": [400, 1800, 6000]},
	"range":      {"name": "Laser range",      "levels": [{"reach": 2500}, {"reach": 3500}, {"reach": 5000}, {"reach": 7000}], "costs": [2500, 9000, 25000]},
	"hull":       {"name": "Hull plating",     "levels": [{"hp": 100}, {"hp": 160}, {"hp": 250}, {"hp": 400}, {"hp": 600}], "costs": [250, 900, 3000, 9000]},
	"thrusters":  {"name": "Afterburner",      "levels": [{"mult": 1}, {"mult": 2}, {"mult": 3}, {"mult": 4}, {"mult": 5}], "costs": [800, 3000, 9000, 24000]},
	"overcharge": {"name": "Laser overcharge", "levels": [{"mult": 1.0}, {"mult": 1.5}, {"mult": 2.0}, {"mult": 2.5}, {"mult": 3.0}], "costs": [600, 2200, 7000, 18000]},
}

## Fuel burn multiplier for an afterburner setting (0.8 x mult squared: x3.2 at x2, x20 at x5)
static func burn_mult(m: float) -> float:
	return 0.8 * m * m if m > 1.0 else 1.0

## The Hub's belts are empty; anything with a `zone` is an export and carries the premium at the only market.

## Belt radii are in base units measured outward from the planet's surface; Belt.build multiplies them by WORLD_SCALE.
const BASE_BELTS := [
	{"name": "Inner belt", "rMin": 600.0,  "rMax": 3600.0,  "count": 1000, "size": [18, 62], "amount": [35, 110],  "spread": 650.0},
	{"name": "Mid belt",   "rMin": 3800.0, "rMax": 7000.0,  "count": 925,  "size": [20, 68], "amount": [45, 150],  "spread": 900.0},
	{"name": "Outer belt", "rMin": 7200.0, "rMax": 10500.0, "count": 800,  "size": [22, 74], "amount": [60, 210],  "spread": 1150.0},
]
## The ring belt sits at a fixed distance from the planet's centre (700 km above Ferron's surface), 50 km wide and thin.
const RING_BELT := {"name": "Ring belt", "rMin": 900000.0, "rMax": 950000.0, "count": 5600, "size": [16, 54], "amount": [30, 95], "spread": 9000.0,
	"ores": {"iron": 0.48, "copper": 0.3, "gold": 0.12, "platinum": 0.06, "crystal": 0.04}}

const ZONE_KESSLER := {
	"id": "kessler", "name": "Kessler Belt", "hub": false, "map": Vector2(46, 34), "danger": 0.5,
	"tag": "The home belt. Picked over, safe, and never far from a refuel.",
	"density": 5.0, "amountMult": 1.0,
	"belts": [
		{"iron": 0.55, "copper": 0.25, "cobalt": 0.2},
		{"copper": 0.3, "gold": 0.4, "platinum": 0.1, "cobalt": 0.1, "beryl": 0.1},
		{"gold": 0.15, "platinum": 0.4, "crystal": 0.25, "beryl": 0.2},
	],
	"planet": {"name": "Ferron", "r": 900.0, "tint": Color("#7E5F4B"), "central": true},
	"sunDir": Vector3(0.55, 0.42, -0.72), "bg": Color("#070912"),
}
## The Hub: Meridian Colony at the origin, no belts and no central gravity; the homeworld hangs below the colony lanes.
const ZONE_HUB := {
	"id": "hub", "name": "The Hub", "hub": true, "colony": "Meridian Colony", "map": Vector2(50, 57), "danger": 0.0,
	"tag": "Meridian Colony above a blue ocean world. Green continents, white clouds, and familiar lights on the night side: a home to return to, with safe lanes and the sector's ore market.",
	"density": 0.0, "amountMult": 1.0,
	"belts": [{}, {}, {}],
	"planet": {"name": "Meridian", "r": 1280.0, "tint": Color("#3C86B5"), "central": false, "position": Vector3(150000.0, -430000.0, -360000.0)},
	"sunDir": Vector3(-0.85, 0.45, 0.10), "bg": Color("#080a14"),
}
const ZONES := [ZONE_HUB, ZONE_KESSLER]

## The colony market: fuel and repair parts for the cargo ship, and how prices drift.
const CARGO_FUEL_PRICE := 0.6
const PARTS_PRICE := 2.0
const MARKET_PERIOD := 90.0

## Where the cargo ship holds station off Meridian Colony (true world coordinates) and the heading it holds, nose toward the hub.
const HOLD_PARK := Vector3(-40000.0, 14000.0, 56000.0)
const HOLD_DIR := Vector3(40000.0, -9000.0, -56000.0)

## Meridian Colony's proportions (the HTML's COLONY constants).
const COLONY := {"R": 52000.0, "ringW": 3000.0, "ringH": 2600.0, "R2": 30000.0, "ring2W": 1800.0, "ring2H": 1800.0, "hub": 7000.0, "coreR": 2600.0, "coreH": 24000.0, "padY": 15000.0, "padR": 5200.0, "berthY": 12000.0, "termX": 4200.0, "termY": 1500.0, "termZ": 3200.0, "berthZ": 6230.0}


static func zone_by_id(id: String) -> Dictionary:
	for z in ZONES:
		if z["id"] == id:
			return z
	return ZONE_KESSLER


## Light-years between two zones, from their chart positions.
static func zone_ly(a: Dictionary, b: Dictionary) -> float:
	var pa: Vector2 = a["map"]
	var pb: Vector2 = b["map"]
	return roundf(pa.distance_to(pb) * 0.12 * 10.0) / 10.0


static func fmt(n: float) -> String:
	var s := str(roundi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0 and s[i - 1] != "-":
			out = "," + out
	return out


## A readout distance: world units to metres, with thousands separators
static func fm(n: float) -> String:
	return fmt(n * METRE)
