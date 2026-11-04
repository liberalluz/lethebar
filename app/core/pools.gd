class_name Pools
extends RefCounted

## Item pools (engine-bricks §6). A pool is a named list a package draws from;
## a draw takes items out unless the pool says otherwise, and what is left is
## part of the save, so reloading cannot re-roll it. Order is not shuffled when
## the file loads: the shuffle happens on the first draw, through the session
## RNG, which keeps a fresh run reproducible.

const ID_PATTERN := "^[a-z][a-z0-9_]*$"

static var _id_re: RegEx


static func _id_pattern() -> RegEx:
	if _id_re == null:
		_id_re = RegEx.new()
		_id_re.compile(ID_PATTERN)
	return _id_re


static func list(pools: Variant) -> Array:
	## The declared pools, in file order, as written.
	if pools is Array:
		return pools
	return []


static func by_id(pools: Variant, pool_id: String) -> Dictionary:
	for pool in list(pools):
		if pool is Dictionary and String(pool.get("id", "")) == pool_id:
			return pool
	return {}


static func items(pool: Dictionary) -> Array:
	var out: Array = []
	if pool.get("items", null) is Array:
		for item in pool["items"]:
			out.append(String(item))
	return out


static func draw_size(pool: Dictionary) -> int:
	var draw: Variant = pool.get("draw", null)
	if draw is Dictionary:
		return int(draw.get("n", 1))
	return 1


static func replaces(pool: Dictionary) -> bool:
	var draw: Variant = pool.get("draw", null)
	if draw is Dictionary:
		return bool(draw.get("replace", false))
	return false


static func problems(pools: Variant) -> Array:
	## Everything an author can get wrong about a pool, as plain strings; the
	## validator turns each one into V-19. Drawing more than the pool holds is
	## only wrong when the pool is not refilled (engine-bricks §6).
	var out: Array = []
	if pools == null:
		return out
	if not (pools is Array):
		out.append("data/pools.json must be an object with a pools array")
		return out
	var seen_ids: Array = []
	for pool in pools:
		if not (pool is Dictionary):
			out.append("a pool must be an object")
			continue
		var pool_id := String(pool.get("id", ""))
		if not _id_pattern().search(pool_id):
			out.append("pool id %s does not match %s" % [pool_id, ID_PATTERN])
		elif seen_ids.has(pool_id):
			out.append("pool id %s is declared twice" % pool_id)
		else:
			seen_ids.append(pool_id)
		if not (pool.get("items", null) is Array):
			out.append("pool %s has no items array" % pool_id)
			continue
		var seen_items: Array = []
		for item in pool["items"]:
			var text := String(item)
			if seen_items.has(text):
				out.append("pool %s lists %s twice" % [pool_id, text])
			else:
				seen_items.append(text)
		if pool.get("draw", null) != null and not (pool["draw"] is Dictionary):
			out.append("pool %s has a draw that is not an object" % pool_id)
			continue
		if draw_size(pool) < 1:
			out.append("pool %s draws %d items" % [pool_id, draw_size(pool)])
		elif not replaces(pool) and draw_size(pool) > seen_items.size():
			out.append(
				"pool %s draws %d items from %d without replace"
				% [pool_id, draw_size(pool), seen_items.size()]
			)
	return out


static func remaining(pools: Variant) -> Dictionary:
	## The starting contents of every pool, before anything is drawn.
	var out: Dictionary = {}
	for pool in list(pools):
		if pool is Dictionary:
			out[String(pool.get("id", ""))] = items(pool)
	return out


static func draw(
	pool: Dictionary, left: Array, rng: int, shuffled: bool
) -> Dictionary:
	## Takes one draw out of a pool and returns the items, what is left, the RNG
	## after the draw and whether the pool has been shuffled. The pool is
	## shuffled once, on its first draw, so a fresh run is reproducible from the
	## seed and a restored run keeps its order (engine-bricks §6).
	var state := rng
	var order: Array = left.duplicate()
	if not shuffled:
		state = _shuffle(order, state)
	var size := maxi(draw_size(pool), 1)
	var taken: Array = []
	var rest: Array = []
	if replaces(pool):
		for i in size:
			state = _step(state)
			if order.is_empty():
				break
			taken.append(order[state % order.size()])
		rest = order
	else:
		for i in size:
			if order.is_empty():
				break
			state = _step(state)
			var index := state % order.size()
			taken.append(order[index])
			order.remove_at(index)
		rest = order
	return {"items": taken, "remaining": rest, "rng": state, "shuffled": true}


static func _shuffle(order: Array, rng: int) -> int:
	## Fisher-Yates driven by the session RNG: the same seed and the same pool
	## produce the same order, and nothing about the file order is exposed.
	var state := rng
	for i in range(order.size() - 1, 0, -1):
		state = _step(state)
		var j := state % (i + 1)
		var swap: Variant = order[i]
		order[i] = order[j]
		order[j] = swap
	return state


static func _step(rng: int) -> int:
	## xorshift32, the same generator the session uses for its seed.
	var x := rng & 0xFFFFFFFF
	x = x ^ ((x << 13) & 0xFFFFFFFF)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & 0xFFFFFFFF)
	x = x & 0x7FFFFFFF
	return x if x != 0 else 1
