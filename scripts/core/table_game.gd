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
const ROUNDS := 3
const OUT_BONUS := 150
const GOLD_CHIPS := 25
const THIEF_STEAL := 20
const GOLD_TILES := 4
const THIEF_TILES := 3
const WILD_TILES := 3


class Seat:
	var name := ""
	var character: Dictionary = {}
	var personality := ""
	var is_bot := false
	var hand: Array[int] = []
	var total := 0
	var meld_count := 0
	var last := ""


var seats: Array[Seat] = []
var wall: Array[int] = []
var discard: Array[int] = []
var current := 0
var phase: Phase = Phase.ENDED
var round_number := 0
var turn_melds := 0
var end_info: Dictionary = {}


func add_seat(seat_name: String, character_id: String, personality := "") -> void:
	var s := Seat.new()
	s.name = seat_name
	s.character = Characters.get_by_id(character_id)
	s.personality = personality
	s.is_bot = personality != ""
	seats.append(s)


func start_round() -> void:
	round_number += 1
	_build_wall()
	discard.clear()
	for s in seats:
		s.hand.clear()
		s.meld_count = 0
		s.last = ""
	for i in HAND_SIZE:
		for s in seats:
			s.hand.append(wall.pop_back())
	for s in seats:
		if s.character.get("start_wild", false):
			s.hand.pop_back()
			s.hand.append(Meld.WILD_TILE)
	discard.append(wall.pop_back())
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
	return _err("Unknown action")


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
	var tile: int
	if source == "discard":
		if discard.is_empty():
			return _err("Discard pile is empty")
		tile = discard.pop_back()
	else:
		if wall.is_empty():
			return _err("Wall is empty")
		tile = wall.pop_back()
	seats[si].hand.append(tile)
	seats[si].last = "DREW " + ("DISCARD" if source == "discard" else "WALL")
	phase = Phase.ACT
	return {"ok": true, "type": "draw", "from": source, "tile": tile}


func _compute(si: int, tiles: Array, m: Dictionary) -> Dictionary:
	var ch: Dictionary = seats[si].character
	var base_chips: int = int(m.chips) + int(ch.get("meld_chips", 0))
	var base_mult: int = int(m.mult) + int(ch.get("%s_mult" % m.kind, 0))

	var remaining: Array = m.tiles.duplicate()
	var steps: Array[int] = []
	var thieves := 0
	for t: int in tiles:
		var power := Meld.power_of(t)
		if power == Meld.WILD:
			steps.append(-1)
			continue
		remaining.erase(t % 100)
		var step := Meld.rank_of(t)
		if power == Meld.GOLD:
			step += GOLD_CHIPS
		elif power == Meld.THIEF:
			thieves += 1
		steps.append(step)
	for i in steps.size():
		if steps[i] == -1:
			steps[i] = Meld.rank_of(remaining.pop_front())

	var chips := base_chips
	for st in steps:
		chips += st
	var combo := turn_melds
	var mult := base_mult + combo
	return {
		"name": m.name, "kind": m.kind, "tiles": tiles.duplicate(), "steps": steps,
		"base_chips": base_chips, "base_mult": base_mult, "combo": combo,
		"chips": chips, "mult": mult, "total": chips * mult, "thieves": thieves,
	}


func _meld(si: int, tiles: Array) -> Dictionary:
	if phase != Phase.ACT:
		return _err("Draw a tile first")
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
	s.meld_count += 1
	turn_melds += 1
	s.last = "%s +%d" % [r.name, r.total]

	r["ok"] = true
	r["type"] = "meld"
	r["stolen"] = stolen
	r["victim"] = victim
	r["out"] = s.hand.is_empty()
	if r.out:
		_go_out(si)
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
		_go_out(si)
	else:
		_advance()
	return {"ok": true, "type": "discard", "tile": tile, "out": out}


func _go_out(si: int) -> void:
	seats[si].total += OUT_BONUS
	phase = Phase.ENDED
	end_info = {"reason": "out", "winner": si}


func _advance() -> void:
	current = (current + 1) % seats.size()
	phase = Phase.DRAW
	turn_melds = 0
	if wall.is_empty():
		phase = Phase.ENDED
		end_info = {"reason": "wall", "winner": -1}
