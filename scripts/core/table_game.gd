class_name TableGame
extends RefCounted
## Authoritative rules engine for a Megajong table. No UI or networking in here:
## every change goes through apply(seat, action) with a plain-Dictionary action, so the
## same engine can be driven by the local UI, bots, or (later) remote clients on a host.
##
## Turn: DRAW (wall or top of discard) -> ACT (lay any number of melds, each scoring
## chips x mult with +1 mult per earlier meld this turn) -> discard one tile to end the turn.
## Emptying your hand "goes out": +OUT_BONUS and the round ends.
##
## Actions:
##   {"type": "draw", "from": "wall" | "discard"}
##   {"type": "meld", "tiles": [int, ...]}
##   {"type": "discard", "tile": int}

enum Phase { DRAW, ACT, ENDED }

const HAND_SIZE := 10
## Game modes. hand: starting tiles; refill: tiles drawn after each non-final meld (+1 more for a
## 5-tile meld when refill > 0); max_melds: per-turn cap (0 = unlimited); sum15: allow the sum-15 meld;
## meld_out: going out must be done by a meld (a discard can't empty the hand).
const RULESETS := {
	"classic": {"name": "CLASSIC", "desc": "10 tiles, no limits", "hand": 10, "refill": 0, "max_melds": 0, "sum15": true, "meld_out": false},
	"mega": {"name": "MEGA", "desc": "12 tiles, refill, 2 melds/turn", "hand": 12, "refill": 1, "max_melds": 2, "sum15": false, "meld_out": true},
	"marathon": {"name": "MARATHON", "desc": "14 tiles, refill, 3 melds/turn", "hand": 14, "refill": 1, "max_melds": 3, "sum15": false, "meld_out": true},
}
const RULE_IDS := ["classic", "mega", "marathon"]
const ROUNDS := 3
const OUT_BONUS := 150
const GOLD_CHIPS := 25
const THIEF_STEAL := 20
const GOLD_TILES := 4
const THIEF_TILES := 3
const WILD_TILES := 3
const GOLD_RUSH_CHIPS := 40
const WILD_DRAGON_MULT := 3
const CHAIN_MULT := 2
## Power-up cards ride in the wall (encoded POWER_BASE + index). Drawing one stashes it in the
## drawer's inventory and keeps drawing until a real tile turns up.
const POWER_BASE := 400
const POWER_CARDS := 7
const SURGE_BOOST := 3
const POWERUPS := {
	"swap": {"name": "SWAP", "desc": "Trade 1 selected tile for a random tile from a rival"},
	"draw3": {"name": "DRAW 3", "desc": "Draw 3 extra tiles from the wall"},
	"dump3": {"name": "DUMP 3", "desc": "Discard 3 selected tiles - empty your hand to go out"},
	"surge": {"name": "SURGE", "desc": "Your next meld this turn gets +3 surge"},
	"skip": {"name": "SKIP", "desc": "The next player loses their turn"},
}
const POWER_IDS := ["swap", "draw3", "dump3", "surge", "skip"]


class Seat:
	var name := ""
	var character: Dictionary = {}
	var personality := ""
	var is_bot := false
	var hand: Array[int] = []
	var total := 0
	var meld_count := 0
	var last := ""
	var powerups: Array[String] = []


var seats: Array[Seat] = []
var wall: Array[int] = []
var discard: Array[int] = []
var current := 0
var phase: Phase = Phase.ENDED
var round_number := 0
var turn_melds := 0
var end_info: Dictionary = {}
var surge_next := 0
var last_kind := ""
var rule_id := "mega"
var rules: Dictionary = RULESETS["mega"]


func set_rules(id: String) -> void:
	rule_id = id if RULESETS.has(id) else "mega"
	rules = RULESETS[rule_id]
	Meld.sum15_enabled = bool(rules.sum15)
var skip_pending := false


func add_seat(seat_name: String, character_id: String, personality := "") -> void:
	var s := Seat.new()
	s.name = seat_name
	s.character = Characters.get_by_id(character_id)
	s.personality = personality
	s.is_bot = personality != ""
	seats.append(s)


func start_round() -> void:
	set_rules(rule_id)
	round_number += 1
	_build_wall()
	discard.clear()
	for s in seats:
		s.hand.clear()
		s.meld_count = 0
		s.last = ""
		s.powerups.clear()
	surge_next = 0
	last_kind = ""
	skip_pending = false
	for i in int(rules.hand):
		for s in seats:
			s.hand.append(wall.pop_back())
	for s in seats:
		if s.character.get("start_wild", false):
			s.hand.pop_back()
			s.hand.append(Meld.WILD_TILE)
	discard.append(wall.pop_back())
	# Added after the deal so nobody starts holding one.
	for i in POWER_CARDS:
		wall.insert(randi() % (wall.size() + 1), POWER_BASE + i % POWER_IDS.size())
	current = (round_number - 1) % seats.size()
	phase = Phase.DRAW
	turn_melds = 0
	end_info = {}


func is_over() -> bool:
	return phase == Phase.ENDED and round_number >= ROUNDS


## Seat indices ordered best score first.
func standings() -> Array[int]:
	var order: Array[int] = []
	for i in seats.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return seats[a].total > seats[b].total)
	return order


func apply(si: int, action: Dictionary) -> Dictionary:
	if phase == Phase.ENDED or si != current:
		return _err("Not your turn")
	match action.get("type", ""):
		"draw":
			return _draw(si, str(action.get("from", "wall")))
		"meld":
			return _meld(si, action.get("tiles", []))
		"discard":
			return _discard(si, int(action.get("tile", -1)))
		"power":
			return _power(si, action)
	return _err("Unknown action")


## Every meld the hand could lay right now, best score first. [{tiles, name, total}]
func hints(si: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cap := int(rules.max_melds)
	if cap > 0 and turn_melds >= cap:
		return out
	var hand: Array = seats[si].hand
	var combos: Array = []
	for size in range(3, 6):
		Bot._combos(hand, size, 0, [], combos)
	var seen := {}
	for c: Array in combos:
		c.sort()
		var key := str(c)
		if seen.has(key):
			continue
		seen[key] = true
		var m := Meld.evaluate(c)
		if m.is_empty():
			continue
		var r := _compute(si, c, m)
		out.append({"tiles": c, "name": r.name, "total": r.total})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.total > b.total)
	return out


## Score breakdown for a meld without changing any state. {} if not a valid meld.
func preview(si: int, tiles: Array) -> Dictionary:
	var m := Meld.evaluate(tiles)
	if m.is_empty():
		return {}
	return _compute(si, tiles, m)


func _build_wall() -> void:
	wall.clear()
	for base: int in Meld.BASE_TILES:
		for copy in 4:
			wall.append(base)
	wall.shuffle()
	for i in GOLD_TILES:
		wall[i] += Meld.GOLD * 100
	for i in THIEF_TILES:
		wall[GOLD_TILES + i] += Meld.THIEF * 100
	for i in WILD_TILES:
		wall.append(Meld.WILD_TILE)
	wall.shuffle()


func _err(message: String) -> Dictionary:
	return {"ok": false, "err": message}


func _draw(si: int, source: String) -> Dictionary:
	if phase != Phase.DRAW:
		return _err("Already drew - meld or discard")
	var tile := -1
	var found: Array[String] = []
	if source == "discard":
		if discard.is_empty():
			return _err("Discard pile is empty")
		tile = discard.pop_back()
	else:
		if wall.is_empty():
			return _err("Wall is empty")
		var drawn := _take_from_wall(si, 1)
		found = drawn.found
		tile = drawn.tiles[0] if not drawn.tiles.is_empty() else -1
	if tile >= 0:
		seats[si].hand.append(tile)
	seats[si].last = "DREW " + ("DISCARD" if source == "discard" else "WALL")
	phase = Phase.ACT
	return {"ok": true, "type": "draw", "from": source, "tile": tile, "found": found}


## Pulls up to `count` real tiles off the wall; power-up cards met on the way go to `si`'s inventory.
func _take_from_wall(si: int, count: int) -> Dictionary:
	var tiles: Array[int] = []
	var found: Array[String] = []
	while tiles.size() < count and not wall.is_empty():
		var t: int = wall.pop_back()
		if t >= POWER_BASE:
			var id: String = POWER_IDS[t - POWER_BASE]
			seats[si].powerups.append(id)
			found.append(id)
		else:
			tiles.append(t)
	return {"tiles": tiles, "found": found}


func _power(si: int, action: Dictionary) -> Dictionary:
	if phase != Phase.ACT:
		return _err("Draw a tile first")
	var id := str(action.get("id", ""))
	var s := seats[si]
	if not s.powerups.has(id):
		return _err("You don't have that power-up")
	var picked: Array = action.get("tiles", [])
	var res := {"ok": true, "type": "power", "id": id}
	match id:
		"swap":
			var target := int(action.get("target", -1))
			if target < 0 or target >= seats.size() or target == si or seats[target].hand.is_empty():
				return _err("Pick a rival to swap with")
			if picked.size() != 1 or not s.hand.has(int(picked[0])):
				return _err("Select 1 tile to trade")
			var other := seats[target]
			var gave := int(picked[0])
			var got: int = other.hand[randi() % other.hand.size()]
			s.hand.erase(gave)
			other.hand.erase(got)
			s.hand.append(got)
			other.hand.append(gave)
			other.last = "TRADED WITH " + s.name
			res.merge({"target": target, "gave": gave, "got": got})
		"draw3":
			if wall.is_empty():
				return _err("Wall is empty")
			var drawn := _take_from_wall(si, 3)
			s.hand.append_array(drawn.tiles)
			res["tiles"] = drawn.tiles
			res["found"] = drawn.found
		"dump3":
			var need := mini(3, s.hand.size())
			if picked.size() != need:
				return _err("Select %d tiles to dump" % need)
			var pool: Array = s.hand.duplicate()
			for t in picked:
				var i := pool.find(int(t))
				if i < 0:
					return _err("Tile not in hand")
				pool.remove_at(i)
			s.hand.assign(pool)
			for t in picked:
				discard.append(int(t))
			res["tiles"] = picked.duplicate()
		"surge":
			surge_next += SURGE_BOOST
		"skip":
			if skip_pending:
				return _err("Next player is already skipped")
			skip_pending = true
	s.powerups.erase(id)
	s.last = "USED " + String(POWERUPS[id].name)
	res["out"] = s.hand.is_empty()
	if res.out:
		_go_out(si)
	return res


func _compute(si: int, tiles: Array, m: Dictionary) -> Dictionary:
	var ch: Dictionary = seats[si].character
	var base_chips: int = int(m.chips) + int(ch.get("meld_chips", 0))
	var base_mult: int = int(m.mult) + int(ch.get("%s_mult" % m.kind, 0))

	var remaining: Array = m.tiles.duplicate()
	var steps: Array[int] = []
	var thieves := 0
	var golds := 0
	var wilds := 0
	for t: int in tiles:
		var power := Meld.power_of(t)
		if power == Meld.WILD:
			wilds += 1
			steps.append(-1)
			continue
		remaining.erase(t % 100)
		var step := Meld.rank_of(t)
		if power == Meld.GOLD:
			step += GOLD_CHIPS
			golds += 1
		elif power == Meld.THIEF:
			thieves += 1
		steps.append(step)
	for i in steps.size():
		if steps[i] == -1:
			steps[i] = Meld.rank_of(remaining.pop_front())

	var bonuses: Array[String] = []
	var name: String = m.name
	if golds >= 2:
		base_chips += GOLD_RUSH_CHIPS
		bonuses.append("GOLD RUSH")
	if thieves > 0 and golds > 0:
		thieves += 1
		bonuses.append("THIEF RING")
	if wilds >= 2:
		base_mult += WILD_DRAGON_MULT
		name = "DRAGON " + name
	var chain := CHAIN_MULT if turn_melds > 0 and last_kind != "" and last_kind != m.kind else 0

	var chips := base_chips
	for st in steps:
		chips += st
	var combo := turn_melds
	var mult := base_mult + combo + surge_next + chain
	return {
		"name": name, "kind": m.kind, "tiles": tiles.duplicate(), "steps": steps,
		"bonuses": bonuses, "chain": chain,
		"base_chips": base_chips, "base_mult": base_mult, "combo": combo, "surge": surge_next,
		"chips": chips, "mult": mult, "total": chips * mult, "thieves": thieves,
	}


func _meld(si: int, tiles: Array) -> Dictionary:
	if phase != Phase.ACT:
		return _err("Draw a tile first")
	var cap := int(rules.max_melds)
	if cap > 0 and turn_melds >= cap:
		return _err("Meld limit: %d per turn" % cap)
	var s := seats[si]
	var pool: Array = s.hand.duplicate()
	for t in tiles:
		var i := pool.find(int(t))
		if i < 0:
			return _err("Tile not in hand")
		pool.remove_at(i)
	var m := Meld.evaluate(tiles)
	if m.is_empty():
		return _err("Not a meld")
	var r := _compute(si, tiles, m)
	s.hand.assign(pool)

	var stolen := 0
	var victim := -1
	for k in int(r.thieves):
		var target := -1
		for j in seats.size():
			if j != si and (target < 0 or seats[j].total > seats[target].total):
				target = j
		var amount := mini(THIEF_STEAL, seats[target].total)
		if amount > 0:
			seats[target].total -= amount
			stolen += amount
			victim = target
	s.total += int(r.total) + stolen
	surge_next = 0
	last_kind = str(r.kind)
	s.meld_count += 1
	turn_melds += 1
	s.last = "%s +%d" % [r.name, r.total]

	r["ok"] = true
	r["type"] = "meld"
	r["stolen"] = stolen
	r["victim"] = victim
	r["out"] = s.hand.is_empty()
	r["refill"] = []
	if r.out:
		_go_out(si)
	elif int(rules.refill) > 0:
		var count := int(rules.refill) + (1 if tiles.size() >= 5 else 0)
		var drawn := _take_from_wall(si, count)
		s.hand.append_array(drawn.tiles)
		r["refill"] = drawn.tiles
		r["found"] = drawn.found
	return r


func _discard(si: int, tile: int) -> Dictionary:
	if phase != Phase.ACT:
		return _err("Draw a tile first")
	var s := seats[si]
	var i := s.hand.find(tile)
	if i < 0:
		return _err("Tile not in hand")
	s.hand.remove_at(i)
	discard.append(tile)
	s.last = "DISCARDED"
	var out := s.hand.is_empty()
	if out:
		_go_out(si, not bool(rules.meld_out))
	else:
		_advance()
	return {"ok": true, "type": "discard", "tile": tile, "out": out}


func _go_out(si: int, bonus := true) -> void:
	var points := OUT_BONUS if bonus else 0
	seats[si].total += points
	phase = Phase.ENDED
	end_info = {"reason": "out", "winner": si, "bonus": points}


func _advance() -> void:
	current = (current + 1) % seats.size()
	if skip_pending:
		skip_pending = false
		seats[current].last = "SKIPPED"
		current = (current + 1) % seats.size()
	phase = Phase.DRAW
	turn_melds = 0
	surge_next = 0
	last_kind = ""
	if wall.is_empty():
		phase = Phase.ENDED
		end_info = {"reason": "wall", "winner": -1}
