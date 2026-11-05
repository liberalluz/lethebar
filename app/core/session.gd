class_name Session
extends RefCounted
## One playthrough of one plugin (SDD §6).
##
## The session owns everything that changes while playing: the current node, the
## mechanic-owned state, the RNG state and the warning list. It reads no clock,
## no disk and no storage — the plugin data arrives inside the install entry, and
## everything else is derived from that data and from the start counter.

const DEFAULT_START_COUNTER := 1

var manifest: Dictionary
var plugin_id: String
var plugin_version: String
var save_schema: int
var protocol_id: String
var protocol: Object
var nodes: Dictionary
var mechanics: Dictionary
var entry_node: String
var current: String
var state: Dictionary
var visited: Array
var warnings: Array
var rng: int
var finished: bool
var locale: String
var i18n: Dictionary
var ledger: Dictionary
var ledger_defs: Dictionary
var rules: Array
var actions: Array
var checks: Array
var phase: Dictionary
var pools: Array
var pools_left: Dictionary
var pools_shuffled: Dictionary
var drawn: Array
var factions: Dictionary
var turn: int
var tick: int
var clock_per: String
var used: Dictionary
var fail_reason: String


static func create(entry: Dictionary, options: Dictionary = {}) -> Session:
	## Builds a session for an installed plugin entry. `options.start_counter`
	## picks which playthrough this is; it is the only source of the seed, so the
	## same counter always reproduces the same run (SDD §6.3).
	if entry.is_empty():
		return null
	var session := Session.new()
	session.manifest = entry.get("manifest", {})
	session.plugin_id = String(entry.get("id", ""))
	session.plugin_version = String(entry.get("version", ""))
	session.save_schema = int(session.manifest.get("saveSchema", 0))
	session.protocol_id = String(session.manifest.get("protocol", ""))
	session.entry_node = String(session.manifest.get("entry", ""))
	session.visited = []
	session.warnings = []
	session.finished = false
	session.current = ""
	session.nodes = {}
	session.mechanics = {}
	session.rules = []
	var data: Dictionary = entry.get("data", {})
	session.ledger = data.get("ledger", {}) if data.get("ledger", null) is Dictionary else {}
	session.ledger_defs = Ledger.definitions(session.ledger)
	session.state = Ledger.initial(session.ledger_defs)
	for node in data.get("nodes", []):
		if node is Dictionary and node.has("id"):
			session.nodes[String(node["id"])] = node
	if data.get("mechanics", null) is Dictionary:
		session.mechanics = data["mechanics"]
	session.rules = data.get("rules", []) if data.get("rules", null) is Array else []
	session.actions = data.get("actions", []) if data.get("actions", null) is Array else []
	session.checks = data.get("checks", []) if data.get("checks", null) is Array else []
	session.phase = Phases.defines(data.get("phases", {}) if data.get("phases", null) is Dictionary else {})
	session.pools = data.get("pools", []) if data.get("pools", null) is Array else []
	session.pools_left = Pools.remaining(session.pools)
	session.pools_shuffled = {}
	session.drawn = []
	session.factions = Relations.defines(data.get("factions", {}) if data.get("factions", null) is Dictionary else {})
	session.turn = 1
	# The clock is the engine's own count of advances, never the wall clock; a
	# package may say which advance it counts (engine-bricks §8). Empty means it
	# counts everything, which is what a package that declares no clock gets.
	var clock: Variant = session.manifest.get("clock", {})
	session.clock_per = String(clock.get("per", "")) if clock is Dictionary else ""
	session.tick = 0
	session.used = {}
	session.fail_reason = ""
	session.i18n = data.get("i18n", {}) if data.get("i18n", null) is Dictionary else {}
	session.locale = String(options.get("locale", ""))
	var counter := int(options.get("start_counter", DEFAULT_START_COUNTER))
	session.rng = ((session.plugin_id.hash() ^ (counter * 2654435761)) & 0x7FFFFFFF) | 1
	session.protocol = ProtocolRegistry.implementation(session.protocol_id)
	if session.protocol == null:
		session.reject("S-01", "no implementation for protocol %s" % session.protocol_id)
		return null
	return session


func start() -> Dictionary:
	if protocol == null:
		return view()
	return protocol.start(self)


func choose(index: int) -> Dictionary:
	if protocol == null or finished:
		return view()
	return protocol.advance(self, {"choice": int(index)})


func goto(next_id: String) -> Dictionary:
	if next_id == "" or not nodes.has(next_id):
		reject("S-02", "node %s does not exist" % next_id)
		return view()
	current = next_id
	visited.append(current)
	if clock_per != "turn":
		tick += 1
	_step_rng()
	apply_rules()
	var node: Dictionary = nodes[current]
	finished = choices_of(node).is_empty()
	return view()


func apply_rules() -> void:
	## Rules see the tick the way they see a resource, but only the engine can
	## move it: a package that tries to write it is refused at install (V-14).
	var result := Mechanics.apply(rules, state, {ManifestSchema.TICK_KEY: float(tick)})
	state = _clamped(result["state"])
	_absorb(result["warnings"])


func apply_effects(effects: Array) -> void:
	var result := Mechanics.apply_effects(effects, state)
	state = _clamped(result["state"])
	_absorb(result["warnings"])


func _clamped(values: Dictionary) -> Dictionary:
	## A declared bound is a clamp, not a refusal: the story keeps playing and the
	## number stops at its edge (engine-bricks §1).
	if ledger_defs.is_empty():
		return values
	var out := values.duplicate(true)
	for id in ledger_defs:
		if out.has(id) and (out[id] is int or out[id] is float):
			out[id] = Ledger.clamp_value(ledger_defs, String(id), float(out[id]))
	return out


func _state_labels() -> Dictionary:
	var out: Dictionary = {}
	for id in ledger_defs:
		var text := Ledger.label_for(ledger_defs, String(id), float(state.get(id, 0.0)))
		if text != "":
			out[id] = text
	return out


func label_for(id: String) -> String:
	return Ledger.label_for(ledger_defs, id, float(state.get(id, 0.0)))



func act(action_id: String) -> Dictionary:
	## One turn of the menu (engine-bricks §3). Costs and effects are applied to a
	## copy and committed together: if any part is refused nothing is written.
	if finished:
		return view()
	var action := Menu.by_id(actions, action_id)
	if action.is_empty():
		reject("S-04", "no action named %s" % action_id)
		return view()
	var availability := Menu.availability(action, self)
	if not availability["enabled"]:
		reject("S-05", "%s is not available: %s" % [action_id, String(availability["reason"])])
		return view()
	var before := state.duplicate(true)
	var scratch := state.duplicate(true)
	var costs: Variant = action.get("costs", {})
	if costs is Dictionary:
		var paid := Mechanics.apply_effects([costs], scratch)
		_absorb(paid["warnings"])
		scratch = paid["state"]
	var effects: Variant = action.get("effects", [])
	if effects is Array:
		var done := Mechanics.apply_effects(effects, scratch)
		_absorb(done["warnings"])
		scratch = done["state"]
	scratch = _clamped(scratch)
	state = scratch
	Menu.record_use(action, self)
	_step_rng()
	turn += 1
	if clock_per != "node":
		tick += 1
	# A clock that counts turns is the one thing that makes growth happen on an
	# action, so the rules run here as well; without a clock nothing changes.
	if clock_per != "":
		apply_rules()
	_after_turn()
	if state == before:
		pass
	return view()


func resolve(check_id: String) -> Dictionary:
	## A check keeps the numbers that decided it, so the interface can say why
	## (engine-bricks §5). A run only ends here when the package says so.
	if finished:
		return view()
	var result := Checks.resolve(self, check_id)
	_after_turn()
	apply_rules()
	return result


func _after_turn() -> void:
	## The phase machine reads the turn, so the rank needs no bookkeeping; a
	## failing condition ends the run and its reason is what the player is told.
	if Phases.declares(phase):
		var failed := Phases.failure(phase, state)
		if not failed.is_empty():
			fail_reason = String(failed.get("reason", ""))
			finished = true
			return
		if turn > int(phase.get("turns", Phases.DEFAULT_TURNS)):
			finished = true


func draw(pool_id: String) -> Dictionary:
	## One draw out of a pool, through the session RNG so the same seed repeats
	## and a restored run keeps what it already drew (engine-bricks §6).
	var pool := Pools.by_id(pools, pool_id)
	if pool.is_empty():
		reject("S-06", "pool %s does not exist" % pool_id)
		return {"items": [], "remaining": [], "rng": rng, "shuffled": false}
	var left: Array = pools_left.get(pool_id, Pools.items(pool))
	var shuffled := bool(pools_shuffled.get(pool_id, false))
	var result := Pools.draw(pool, left, rng, shuffled)
	rng = int(result["rng"])
	pools_left[pool_id] = result["remaining"]
	pools_shuffled[pool_id] = true
	for item in result["items"]:
		drawn.append({"pool": pool_id, "item": String(item)})
	return result


func relation(from_id: String, to_id: String) -> float:
	## What `from_id` feels about `to_id`. Only that direction: the package owns
	## the numbers and the engine never assumes symmetry (engine-bricks §7).
	return Relations.value(factions, from_id, to_id)


func relation_state(from_id: String, to_id: String) -> String:
	## The first declared threshold crossed, or "" when none is. The state names
	## are the package's; the engine carries none of its own.
	return Relations.state(factions, from_id, to_id)


func faction_map() -> Array:
	var out: Array = []
	for id in factions.get("order", []):
		out.append({"id": String(id), "label": Relations.label(factions, String(id))})
	return out


func rank() -> String:
	return Phases.rank(phase, turn)


func menu() -> Array:
	var out: Array = []
	for action in actions:
		var availability := Menu.availability(action, self)
		out.append({
			"id": String(action.get("id", "")),
			"label": String(action.get("label", action.get("id", ""))),
			"enabled": availability["enabled"],
			"reason": String(availability["reason"]),
		})
	return out


func choices() -> Array:
	return choices_of(nodes.get(current, {}))


func choices_of(node: Dictionary) -> Array:
	var out: Array = []
	if node.get("choices", null) is Array:
		for choice in node["choices"]:
			if choice is Dictionary:
				out.append(choice)
	return out


func reject(code: String, message: String) -> void:
	warnings.append({"code": code, "message": message})


func view() -> Dictionary:
	var node: Dictionary = nodes.get(current, {})
	var labels := choice_labels(node)
	var offered: Array = []
	var choices := choices_of(node)
	for i in choices.size():
		offered.append({"label": String(labels[i]), "next": String(choices[i].get("next", ""))})
	var out := {
		"node": current,
		"text": node_text(node),
		"assets": node.get("assets", []),
		"choices": offered,
		"state": state.duplicate(true),
		"labels": _state_labels(),
		"finished": finished,
		"warnings": warnings.duplicate(true),
	}
	if declares("progress"):
		out["progress"] = {"steps": visited.size(), "nodes": nodes.size()}
	if not (pools as Array).is_empty():
		out["pools"] = _pool_view()
	if Relations.declares(factions):
		out["factions"] = faction_map()
		out["thresholds"] = (factions.get("thresholds", {}) as Dictionary).duplicate(true)
	if Phases.declares(phase):
		out["turn"] = turn
		out["rank"] = rank()
		out["actions"] = menu()
		out["failReason"] = fail_reason
	return out


func snapshot() -> Dictionary:
	## Serialisable payload for a save slot (SDD §7.2). No timestamp: the save
	## layer stamps `savedAt`, which keeps gameplay output reproducible.
	return {
		"schema": save_schema,
		"plugin": plugin_id,
		"version": plugin_version,
		"protocol": protocol_id,
		"node": current,
		"state": state.duplicate(true),
		"rng": rng,
		"visited": visited.duplicate(),
		"finished": finished,
		"turn": turn,
		"tick": tick,
		"used": used.duplicate(true),
		"pools": _pool_snapshot(),
		"drawn": drawn.duplicate(true),
	}


func declares(mechanic_id: String) -> bool:
	if manifest.get("mechanics", null) is Array:
		return manifest["mechanics"].has(mechanic_id)
	return false


func locale_text() -> Dictionary:
	## The table for the locale this session plays in, or an empty one when the
	## package carries no translation for it. An empty table means "read the
	## package's own text", which is the default locale.
	if locale == "" or not i18n.has(locale):
		return {}
	var table: Variant = i18n[locale]
	return table if table is Dictionary else {}


func node_text(node: Dictionary) -> String:
	var entry: Dictionary = _locale_entry(node)
	var translated := String(entry.get("text", ""))
	return translated if translated != "" else String(node.get("text", ""))


func choice_labels(node: Dictionary) -> Array:
	## One label per choice, in the same order. A label the translation leaves
	## out falls back to the package's own text: V-22 refuses a partly covered
	## locale before a session can start, so this is a safety net, not the rule.
	var out: Array = []
	var entry: Dictionary = _locale_entry(node)
	var translated: Variant = entry.get("choices", null)
	var index := 0
	for choice in choices_of(node):
		var label := ""
		if translated is Array and index < translated.size():
			label = String(translated[index])
		if label == "":
			label = String(choice.get("label", ""))
		out.append(label)
		index += 1
	return out


func _locale_entry(node: Dictionary) -> Dictionary:
	var table := locale_text()
	if table.is_empty():
		return {}
	var entry: Variant = table.get(String(node.get("id", "")), null)
	return entry if entry is Dictionary else {}


func _pool_view() -> Array:
	var out: Array = []
	for pool in pools:
		if not (pool is Dictionary):
			continue
		var id := String(pool.get("id", ""))
		out.append({
			"id": id,
			"left": (pools_left.get(id, []) as Array).duplicate(),
			"size": Pools.items(pool).size(),
		})
	return out


func _pool_snapshot() -> Dictionary:
	## What is left of every pool, and whether its order has been fixed by a
	## draw. Both travel in the save, so reloading cannot re-roll a draw.
	var out: Dictionary = {}
	for pool in pools:
		if not (pool is Dictionary):
			continue
		var id := String(pool.get("id", ""))
		out[id] = {
			"left": (pools_left.get(id, []) as Array).duplicate(),
			"shuffled": bool(pools_shuffled.get(id, false)),
		}
	return out


func restore_pools(saved: Variant) -> void:
	if not (saved is Dictionary):
		return
	for id in saved:
		var entry: Variant = saved[id]
		if not (entry is Dictionary):
			continue
		if entry.get("left", null) is Array:
			pools_left[String(id)] = (entry["left"] as Array).duplicate()
		pools_shuffled[String(id)] = bool(entry.get("shuffled", false))


func step_rng() -> void:
	_step_rng()


func _step_rng() -> void:
	## xorshift32 over the seeded state: the RNG advances with the session, so two
	## seeds diverge and the same seed repeats exactly.
	var x := rng & 0xFFFFFFFF
	x = x ^ ((x << 13) & 0xFFFFFFFF)
	x = x ^ (x >> 17)
	x = x ^ ((x << 5) & 0xFFFFFFFF)
	rng = x & 0x7FFFFFFF
	if rng == 0:
		rng = 1


func _absorb(extra: Array) -> void:
	for item in extra:
		warnings.append(item)
