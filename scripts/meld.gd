class_name Meld
## Melds. A tile is encoded as power * 100 + suit * 10 + rank (suit 0-2, rank 1-9).
##   power 0 = normal, 1 = WILD (stands in for any tile), 2 = GOLD, 3 = THIEF.
##   Set: 3-4 tiles of the same rank (any suits). All one suit = "Pure" bonus.
##   Run: 3-5 tiles of the same suit with consecutive ranks.

const WILD := 1
const GOLD := 2
const THIEF := 3
const WILD_TILE := 100

const SET_CHIPS := {3: 30, 4: 60}
const SET_MULT := {3: 3, 4: 5}
const RUN_CHIPS := {3: 20, 4: 40, 5: 70}
const RUN_MULT := {3: 2, 4: 3, 5: 5}
const PURE_SET_BONUS := 2
const BASE_TILES := [
	1, 2, 3, 4, 5, 6, 7, 8, 9,
	11, 12, 13, 14, 15, 16, 17, 18, 19,
	21, 22, 23, 24, 25, 26, 27, 28, 29,
]


static func suit_of(tile: int) -> int:
	return (tile / 10) % 10


static func rank_of(tile: int) -> int:
	return tile % 10


static func power_of(tile: int) -> int:
	return tile / 100


## Returns {} if the tiles are not a valid meld, otherwise
## {name, kind, chips, mult, tiles} where `tiles` has wilds resolved to real tiles.
static func evaluate(tiles: Array) -> Dictionary:
	var n := tiles.size()
	if n < 3 or n > 5:
		return {}
	var fixed: Array = []
	var wilds := 0
	for t: int in tiles:
		if power_of(t) == WILD:
			wilds += 1
		else:
			fixed.append(t % 100)
	if wilds == 0:
		return _eval_plain(fixed)
	if fixed.is_empty() or wilds > 2:
		return {}
	var best := {}
	_search(fixed, wilds, best)
	return best


static func _search(fixed: Array, wilds: int, best: Dictionary) -> void:
	if wilds == 0:
		var m := _eval_plain(fixed)
		if not m.is_empty() and (best.is_empty() or _value(m) > _value(best)):
			best.clear()
			best.merge(m)
		return
	for c: int in BASE_TILES:
		var next := fixed.duplicate()
		next.append(c)
		_search(next, wilds - 1, best)


static func _value(m: Dictionary) -> int:
	var chips: int = m.chips
	for t: int in m.tiles:
		chips += rank_of(t)
	return chips * int(m.mult)


static func _eval_plain(tiles: Array) -> Dictionary:
	var n := tiles.size()
	var ranks: Array[int] = []
	var suits: Array[int] = []
	for t: int in tiles:
		ranks.append(rank_of(t))
		suits.append(suit_of(t))
	ranks.sort()

	var same_rank := ranks.all(func(r: int) -> bool: return r == ranks[0])
	var same_suit := suits.all(func(s: int) -> bool: return s == suits[0])

	if same_rank and n <= 4:
		var mult: int = SET_MULT[n]
		var label := "TRIPLET" if n == 3 else "QUAD"
		if same_suit:
			mult += PURE_SET_BONUS
			label = "PURE " + label
		return {"name": label, "kind": "set", "chips": SET_CHIPS[n], "mult": mult, "tiles": tiles}

	if same_suit:
		var consecutive := true
		for i in range(1, n):
			if ranks[i] != ranks[i - 1] + 1:
				consecutive = false
				break
		if consecutive:
			return {
				"name": "RUN OF %d" % n,
				"kind": "run",
				"chips": RUN_CHIPS[n],
				"mult": RUN_MULT[n],
				"tiles": tiles,
			}
	return {}
