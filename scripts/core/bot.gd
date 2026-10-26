class_name Bot
extends RefCounted
## Bot brains. decide() returns ONE action for the current phase; call it repeatedly until the turn ends.
##
## Personalities:
##   rusher    - lays every meld it can as early as possible to go out fast.
##   collector - hoards for chained melds (combo mult), only cashing in when it can chain 2+, or go out.
##   schemer   - loves power tiles: grabs them from the discard pile, never throws them away, plays them first.


static func decide(g: TableGame, si: int) -> Dictionary:
	var s := g.seats[si]
	if g.phase == TableGame.Phase.DRAW:
		return _decide_draw(g, s)
	return _decide_act(g, s)


static func _decide_draw(g: TableGame, s: TableGame.Seat) -> Dictionary:
	if not g.discard.is_empty():
		var top: int = g.discard.back()
		var hand2: Array = s.hand.duplicate()
		hand2.append(top)
		var take := not best_meld(hand2, top).is_empty()
		if s.personality == "schemer" and Meld.power_of(top) > 0:
			take = true
		if take:
			return {"type": "draw", "from": "discard"}
	return {"type": "draw", "from": "wall"}


static func _decide_act(g: TableGame, s: TableGame.Seat) -> Dictionary:
	var plan := plan_melds(s.hand)
	var cap := int(g.rules.max_melds)
	if cap > 0 and g.turn_melds >= cap:
		plan = []
	if s.powerups.has("dump3") and s.hand.size() <= 3 and g.turn_melds == 0:
		return {"type": "power", "id": "dump3", "tiles": s.hand.duplicate()}
	if s.powerups.has("surge") and not plan.is_empty() and g.surge_next == 0:
		return {"type": "power", "id": "surge"}
	if s.powerups.has("draw3") and plan.is_empty() and g.wall.size() > 12:
		return {"type": "power", "id": "draw3"}
	if s.powerups.has("skip") and not g.skip_pending:
		return {"type": "power", "id": "skip"}
	if not plan.is_empty():
		var cover := 0
		for p: Array in plan:
			cover += p.size()
		var play := true
		if s.personality == "collector":
			play = plan.size() >= 2 or cover >= s.hand.size() or s.hand.size() <= 5 or g.turn_melds > 0
		if play:
			var pick: Array = plan[0]
			if s.personality == "schemer":
				for p: Array in plan:
					if p.any(func(t: int) -> bool: return Meld.power_of(t) > 0):
						pick = p
						break
			return {"type": "meld", "tiles": pick}
	return {"type": "discard", "tile": pick_discard(s)}


## Best-scoring meld in `hand` (optionally forced to include `must`). {} if none.
static func best_meld(hand: Array, must := -1) -> Dictionary:
	var best := {}
	var best_value := -1
	var combos: Array = []
	for size in range(3, 6):
		_combos(hand, size, 0, [], combos)
	var seen := {}
	for c: Array in combos:
		if must >= 0 and not c.has(must):
			continue
		var key := ""
		var sorted_c: Array = c.duplicate()
		sorted_c.sort()
		key = str(sorted_c)
		if seen.has(key):
			continue
		seen[key] = true
		var m := Meld.evaluate(c)
		if m.is_empty():
			continue
		var value := Meld._value(m)
		if value > best_value:
			best_value = value
			best = {"tiles": c, "value": value}
	return best


static func _combos(hand: Array, size: int, start: int, cur: Array, out: Array) -> void:
	if cur.size() == size:
		out.append(cur.duplicate())
		return
	for i in range(start, hand.size()):
		cur.append(hand[i])
		_combos(hand, size, i + 1, cur, out)
		cur.pop_back()


## Greedy list of disjoint melds (each an Array of tiles) the hand could lay down.
static func plan_melds(hand: Array) -> Array:
	var rest: Array = hand.duplicate()
	var plan: Array = []
	while true:
		var b := best_meld(rest)
		if b.is_empty():
			break
		plan.append(b.tiles)
		for t: int in b.tiles:
			rest.erase(t)
	return plan


## Discards the tile that connects least with the rest of the hand.
static func pick_discard(s: TableGame.Seat) -> int:
	var worst: int = s.hand[0]
	var worst_value := 1000
	for i in s.hand.size():
		var t: int = s.hand[i]
		var power := Meld.power_of(t)
		var v := 0
		if power == Meld.WILD:
			v += 30
		elif power > 0:
			v += 10 if s.personality == "schemer" else 4
		for j in s.hand.size():
			if j == i:
				continue
			var o: int = s.hand[j]
			if Meld.power_of(o) == Meld.WILD:
				continue
			if Meld.rank_of(o) == Meld.rank_of(t):
				v += 2
			if Meld.suit_of(o) == Meld.suit_of(t):
				var d: int = absi(Meld.rank_of(o) - Meld.rank_of(t))
				if d == 1:
					v += 2
				elif d == 2:
					v += 1
		if v < worst_value:
			worst_value = v
			worst = t
	return worst
