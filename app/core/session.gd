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
var hand_spec: Dictionary
var hand: Array
var deck: Array
var discard: Array
var assembly: Array


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
	session.rules = (data.get("rules", []) as Array).duplicate(true) if data.get("rules", null) is Array else []
	session.actions = (data.get("actions", []) as Array).duplicate(true) if data.get("actions", null) is Array else []
	session.checks = (data.get("checks", []) as Array).duplicate(true) if data.get("checks", null) is Array else []
	# An absent phases file must stay absent: `Phases.defines({})` fills in the
	# defaults, and `Phases.declares()` then reads every package as having a phase
	# machine. Keeping `{}` here is what lets a node without choices end a run
	# (REQ-026 while the scene learns to draw a menu).
	var raw_phases: Variant = data.get("phases", {})
	if raw_phases is Dictionary and not (raw_phases as Dictionary).is_empty():
		session.phase = Phases.defines(raw_phases)
	else:
		session.phase = {}
	session.pools = (data.get("pools", []) as Array).duplicate(true) if data.get("pools", null) is Array else []
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
	# Dealt once from the declared order, so a save draws the same cards (REQ-036).
	var hand_raw: Variant = data.get("hand", {})
	session.hand_spec = Hand.defines(hand_raw) if hand_raw is Dictionary else {}
	if Hand.declared(session.hand_spec):
		var dealt := Hand.deals(session.hand_spec)
		session.hand = dealt["hand"]
		session.deck = dealt["deck"]
		session.discard = dealt["discard"]
	else:
		session.hand = []
		session.deck = []
		session.discard = []
	session.i18n = data.get("i18n", {}) if data.get("i18n", null) is Dictionary else {}
	# A run can be opened from more than one package (REQ-041). The base entry
	# supplies the nodes, the phases and the entry; the others may only add
	# resources, actions, cards and pools. What two packages both declare is not
	# resolved here: the earlier one keeps it and says so, because override and
	# disable belong to the next batch (ADR-0013).
	session.assembly = [session.plugin_id]
	for extra in options.get("assembly", []):
		if extra is Dictionary and not (extra as Dictionary).is_empty():
			if String((extra as Dictionary).get("target", "")) != "":
				session._apply_layer(extra)
			else:
				session._merge_package(extra)
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
	# A node with no choices used to end the run on its own. That is right for a
	# node graph and wrong for a package played through actions: its entry node
	# offers no choices by design, so the run would be over before the menu could
	# be used (REQ-026). A declared phase keeps the run alive until a turn limit
	# or a failure says otherwise.
	finished = choices_of(node).is_empty() and not Phases.declares(phase)
	return view()


func apply_rules() -> void:
	## Rules see the tick the way they see a resource, but only the engine can
	## move it: a package that tries to write it is refused at install (V-14).
	var result := Mechanics.apply(rules, state, {ManifestSchema.TICK_KEY: float(tick)})
	state = _clamped(result["state"])
	_absorb(result["warnings"])
	_apply_relations(result.get("relations", []))


func _apply_relations(changes: Array) -> void:
	## A rule names a pair and a change; the session owns the map, so it is the
	## only writer (REQ-032). An undeclared pair cannot reach here: V-31 refuses
	## it at install time.
	var entities: Dictionary = factions.get("entities", {})
	for change in changes:
		if not (change is Dictionary):
			continue
		var from_id := String(change.get("from", ""))
		var to_id := String(change.get("to", ""))
		if not entities.has(from_id):
			continue
		var entity: Dictionary = entities[from_id]
		var relations: Variant = entity.get("relations", null)
		if not (relations is Dictionary):
			relations = {}
			entity["relations"] = relations
		var current := 0.0
		var raw: Variant = relations.get(to_id, 0.0)
		if raw is int or raw is float:
			current = float(raw)
		if change.has("add"):
			relations[to_id] = current + float(change["add"])
		elif change.has("value"):
			relations[to_id] = float(change["value"])


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
		var value := float(state.get(id, 0.0))
		var text := Ledger.label_for(ledger_defs, String(id), value)
		if text != "":
			out[id] = localise("resource.%s.%d" % [String(id), int(value)], text)
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
	var draws: Variant = action.get("draw", null)
	if draws is Dictionary:
		# Drawing is part of the action, not a second step: the validator already
		# refused a pool the package never declared (V-26), so this only fails on
		# a package that was built after install.
		var pool_id := String(draws.get("pool", ""))
		if Pools.by_id(pools, pool_id).is_empty():
			reject("S-07", "pool %s does not exist" % pool_id)
			return view()
		draw(pool_id)
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


func play_card(card_id: String) -> Dictionary:
	## Playing a card is one turn (REQ-036). The cost is paid and the effects are
	## applied to the same copy, so a card that cannot be paid for changes
	## nothing — the same rule a menu action follows.
	if finished:
		return view()
	var card := Hand.card(hand_spec, card_id)
	if card.is_empty() or not (hand as Array).has(card_id):
		reject("S-09", "no card named %s in the hand" % card_id)
		return view()
	var costs: Variant = card.get("cost", {})
	if not costs is Dictionary:
		costs = {}
	var before := state.duplicate(true)
	var scratch := state.duplicate(true)
	var paid := Mechanics.apply_effects([costs], scratch)
	_absorb(paid["warnings"])
	scratch = paid["state"]
	for key in costs:
		var name := String(key)
		if not ledger_defs.has(name):
			continue
		var floor: float = ledger_defs[name]["min"]
		if float(scratch.get(name, floor)) < floor:
			reject("S-08", "not enough %s to play %s" % [localise("resource.%s.%d" % [name, int(float(before.get(name, 0.0)))], name), card_id])
			return view()
	var taken := Hand.take({"hand": hand, "deck": deck, "discard": discard}, card_id)
	if taken.is_empty():
		reject("S-09", "no card named %s in the hand" % card_id)
		return view()
	var effects: Variant = card.get("effects", [])
	if effects is Array:
		var done := Mechanics.apply_effects(effects, scratch)
		_absorb(done["warnings"])
		scratch = done["state"]
	state = _clamped(scratch)
	hand = taken["hand"]
	deck = taken["deck"]
	discard = taken["discard"]
	_step_rng()
	turn += 1
	if clock_per != "node":
		tick += 1
	if clock_per != "":
		apply_rules()
	_after_turn()
	if not finished:
		_refill_hand()
	return view()


func _refill_hand() -> void:
	## One turn takes one card out; a reshuffle asks this session for the order,
	## because it has to use the run's seeded generator (REQ-039).
	var filled := Hand.draw_into(
		{"hand": hand, "deck": deck, "discard": discard},
		hand_spec,
		int(hand_spec.get("draw", 0)),
		Callable(self, "_shuffle_cards"),
	)
	hand = filled["hand"]
	deck = filled["deck"]
	discard = filled["discard"]


func _shuffle_cards(cards: Array) -> Array:
	## Fisher-Yates through the run's generator: one seed, one order.
	var out := cards.duplicate()
	for index in range(out.size() - 1, 0, -1):
		var swap := _next_rng() % (index + 1)
		var held: Variant = out[index]
		out[index] = out[swap]
		out[swap] = held
	return out


func _next_rng() -> int:
	_step_rng()
	return rng


func hand_view() -> Array:
	## The cards the scene offers, shaped like the menu: enabled with a reason.
	var out: Array = []
	for card_id in hand:
		var id := String(card_id)
		var card := Hand.card(hand_spec, id)
		var enabled := true
		var reason := ""
		var costs: Variant = card.get("cost", {})
		if costs is Dictionary:
			for key in costs:
				var name := String(key)
				if not ledger_defs.has(name):
					continue
				var change: Variant = costs[key]
				var delta := 0.0
				if change is Dictionary:
					delta = float(change.get("add", 0.0))
				var floor: float = ledger_defs[name]["min"]
				if float(state.get(name, 0.0)) + delta < floor:
					enabled = false
					reason = String(name)
		var entry := {
			"id": id,
			"label": Hand.label_of(hand_spec, id),
			"enabled": enabled,
			"reason": reason,
		}
		var icon := Hand.icon_of(hand_spec, id)
		if icon != "":
			entry["icon"] = icon
		out.append(entry)
	return out


func restore_cards(saved: Variant) -> void:
	## The piles travel with the save; an older payload keeps the dealt hand.
	if not (saved is Dictionary):
		return
	var piles: Dictionary = saved
	if piles.get("hand", null) is Array and piles.get("deck", null) is Array:
		hand = (piles["hand"] as Array).duplicate()
		deck = (piles["deck"] as Array).duplicate()
		discard = (piles.get("discard", []) as Array).duplicate()


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
			fail_reason = localise("failure.%d" % _failure_index(failed), String(failed.get("reason", "")))
			finished = true
			return
		if turn > int(phase.get("turns", Phases.DEFAULT_TURNS)):
			finished = true


func _failure_index(entry: Dictionary) -> int:
	## The position of the failure that ended the run, which is the key its
	## translation is filed under: the story does not invent stable ids for them.
	var index := 0
	for item in phase.get("fail", []):
		if item is Dictionary and item == entry:
			return index
		index += 1
	return 0


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


func drawn_ids() -> Array:
	## The items a run has taken out of its pools, in the order they came, so a
	## condition, a save and the scene all read the same list (engine-bricks §6).
	var out: Array = []
	for entry in drawn:
		if entry is Dictionary:
			out.append(String(entry.get("item", "")))
	return out


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


func localise(key: String, fallback: String) -> String:
	## A label the package wrote, in the locale this session plays in. The table's
	## `strings` section is keyed by the thing being named (`action.farm`,
	## `rank.6`, `resource.standing.2`, `failure.0`); a key it leaves out falls
	## back to the package's own text, never to an empty label (REQ-035).
	var table := locale_text()
	if table.is_empty():
		return fallback
	var strings: Variant = table.get("strings", null)
	if not (strings is Dictionary):
		return fallback
	var translated := String(strings.get(key, ""))
	return translated if translated != "" else fallback


func rank() -> String:
	return localise("rank.%d" % _rank_at(), Phases.rank(phase, turn))


func _rank_at() -> int:
	## The `at` of the rank the run has reached, which is the key its translation
	## is filed under; before the first rank there is no key to look up.
	var at := 0
	for entry in phase.get("ranks", []):
		if entry is Dictionary and turn >= int(entry.get("at", 0)):
			at = int(entry.get("at", 0))
	return at


func menu() -> Array:
	var out: Array = []
	for action in actions:
		var availability := Menu.availability(action, self)
		var action_id := String(action.get("id", ""))
		out.append({
			"id": action_id,
			"label": localise("action.%s" % action_id, String(action.get("label", action_id))),
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


func _merge_package(extra: Dictionary) -> void:
	## Joins one more package into the run. Only additive bricks are merged: the
	## nodes and the phase machine stay the base package's, because a story with
	## two entry points is not a story (ADR-0013).
	assembly.append(String(extra.get("id", "")))
	var data: Dictionary = extra.get("data", {}) if extra.get("data", null) is Dictionary else {}
	_merge_resources(data.get("ledger", {}))
	_merge_actions(data.get("actions", []))
	_merge_pools(data.get("pools", []))
	_merge_cards(data.get("hand", {}))


func _apply_layer(extra: Dictionary) -> void:
	## A layer changes the package it names instead of adding a story (REQ-042).
	## The three semantics are the record's, not code's convenience: a declared
	## resource is replaced wholesale, new entries join the lists they belong to,
	## and the names in `data/disable.json` leave them. A fourth semantic is a new
	## decision, so there is none here (ADR-0013).
	assembly.append(String(extra.get("id", "")))
	var data: Dictionary = extra.get("data", {}) if extra.get("data", null) is Dictionary else {}
	_override_resources(data.get("ledger", {}))
	_merge_actions(data.get("actions", []))
	_merge_pools(data.get("pools", []))
	_merge_cards(data.get("hand", {}))
	_disable(data.get("disable", {}))


func _override_resources(ledger: Variant) -> void:
	if not (ledger is Dictionary):
		return
	for resource in (ledger as Dictionary).get("resources", []):
		if not (resource is Dictionary) or not resource.has("id"):
			continue
		var key := String(resource["id"])
		if not ledger_defs.has(key):
			continue
		var single := Ledger.definitions({"resources": [resource]})
		for name in single:
			ledger_defs[name] = single[name]
			var low := float(single[name].get("min", 0.0))
			var high := float(single[name].get("max", 0.0))
			state[name] = clampf(float(state.get(name, float(single[name].get("init", 0.0)))), low, high)


func _disable(disable: Variant) -> void:
	if not (disable is Dictionary):
		return
	for raw in (disable as Dictionary).get("actions", []):
		var action_id := String(raw)
		for index in range(actions.size() - 1, -1, -1):
			if String((actions[index] as Dictionary).get("id", "")) == action_id:
				actions.remove_at(index)
	for raw in (disable as Dictionary).get("pools", []):
		var pool_id := String(raw)
		for index in range(pools.size() - 1, -1, -1):
			if String((pools[index] as Dictionary).get("id", "")) == pool_id:
				pools.remove_at(index)
		pools_left.erase(pool_id)
	for raw in (disable as Dictionary).get("cards", []):
		var card_id := String(raw)
		for pile in [hand, deck, discard]:
			for index in range((pile as Array).size() - 1, -1, -1):
				if String((pile as Array)[index]) == card_id:
					(pile as Array).remove_at(index)
	for raw in (disable as Dictionary).get("resources", []):
		var key := String(raw)
		ledger_defs.erase(key)
		state.erase(key)


func _merge_resources(ledger: Variant) -> void:
	if not (ledger is Dictionary):
		return
	for resource in (ledger as Dictionary).get("resources", []):
		if not (resource is Dictionary) or not resource.has("id"):
			continue
		var key := String(resource["id"])
		if ledger_defs.has(key):
			reject("W-05", "resource %s is declared twice; the earlier package keeps it" % key)
			continue
		var single := Ledger.definitions({"resources": [resource]})
		for name in single:
			ledger_defs[name] = single[name]
			state[name] = float(single[name].get("init", 0.0))


func _merge_actions(incoming: Variant) -> void:
	if not (incoming is Array):
		return
	var known: Array = []
	for action in actions:
		known.append(String(action.get("id", "")))
	for action in incoming:
		if not (action is Dictionary):
			continue
		var key := String(action.get("id", ""))
		if known.has(key):
			reject("W-05", "action %s is declared twice; the earlier package keeps it" % key)
			continue
		known.append(key)
		actions.append(action)


func _merge_pools(incoming: Variant) -> void:
	if not (incoming is Array):
		return
	var known: Array = []
	for pool in pools:
		known.append(String(pool.get("id", "")))
	for pool in incoming:
		if not (pool is Dictionary):
			continue
		var key := String(pool.get("id", ""))
		if known.has(key):
			reject("W-05", "pool %s is declared twice; the earlier package keeps it" % key)
			continue
		known.append(key)
		pools.append(pool)
		pools_left[key] = Pools.remaining([pool]).get(key, [])


func _merge_cards(incoming: Variant) -> void:
	if not (incoming is Dictionary) or not Hand.declared(hand_spec):
		return
	for rank in ["size", "draw_per_turn", "reshuffle"]:
		if hand_spec.has(rank):
			continue
		hand_spec[rank] = (incoming as Dictionary).get(rank, hand_spec.get(rank))
	var cards: Dictionary = hand_spec.get("cards", {})
	for card_id in (incoming as Dictionary).get("cards", {}):
		if cards.has(card_id):
			reject("W-05", "card %s is declared twice; the earlier package keeps it" % String(card_id))
			continue
		cards[card_id] = incoming["cards"][card_id]
	hand_spec["cards"] = cards
	var extra_deck: Array = (incoming as Dictionary).get("deck", [])
	for card_id in extra_deck:
		if not deck.has(card_id):
			deck.append(card_id)


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
	if not (drawn as Array).is_empty():
		# What has been drawn is part of what the player knows, so the scene can
		# say it and an action can wait on it (REQ-027).
		out["drawn"] = drawn_ids()
	if not (hand as Array).is_empty():
		# A hand is how a card package offers its options; a package without one
		# never grows the key, so a menu-only package looks exactly as before.
		out["hand"] = hand_view()
	if Relations.declares(factions):
		out["factions"] = faction_map()
		out["thresholds"] = (factions.get("thresholds", {}) as Dictionary).duplicate(true)
	if Phases.declares(phase):
		out["turn"] = turn
		out["rank"] = rank()
		out["actions"] = menu()
		out["failReason"] = fail_reason
	var reading := situation()
	if not reading.is_empty():
		out["situation"] = reading
	return out


func situation() -> Dictionary:
	## How the run stands, read once for the scene (REQ-033). Every number comes
	## from what the package declared: the turn budget from phases, the pair
	## values from factions, the floors and ceilings from the ledger. A story that
	## declares none of them gets no reading rather than a made-up one.
	var out := {}
	if not (Phases.declares(phase) or Relations.declares(factions)):
		return out
	if Phases.declares(phase):
		var turns := int(phase.get("turns", Phases.DEFAULT_TURNS))
		out["turnsLeft"] = maxi(turns - turn + 1, 0)
	if Relations.declares(factions):
		var leaning := _standing(true)
		var friction := _standing(false)
		if leaning != "":
			out["leaning"] = leaning
		if friction != "":
			out["friction"] = friction
	if Phases.declares(phase):
		var tight := _tightest()
		if tight != "":
			out["tight"] = tight
	return out


func _standing(high: bool) -> String:
	## Sums the relations each entity receives, so "everyone leans toward Wu" is
	## the total of what the other entities feel, not one direction picked by the
	## engine. Ties keep the declaration order, so the answer is stable.
	var order: Array = factions.get("order", [])
	var best := ""
	var best_score := 0.0
	var found := false
	for entity_id in order:
		var score := 0.0
		for other in order:
			if other == entity_id:
				continue
			score += relation(String(other), String(entity_id))
		if not found or (score > best_score if high else score < best_score):
			best = String(entity_id)
			best_score = score
			found = true
	return best


func _tightest() -> String:
	## The resource closest to its declared floor, measured as the fraction of
	## the range still above it: 1 of 10 is tighter than 20 of 100.
	var best := ""
	var best_fraction := 0.0
	for id in ledger_defs:
		var low: float = ledger_defs[id]["min"]
		var high: float = ledger_defs[id]["max"]
		var span := high - low
		if span <= 0.0:
			continue
		var value := float(state.get(id, low))
		var fraction := clampf((value - low) / span, 0.0, 1.0)
		if best == "" or fraction < best_fraction:
			best = String(id)
			best_fraction = fraction
	return best


func snapshot() -> Dictionary:
	## Serialisable payload for a save slot (SDD §7.2). No timestamp: the save
	## layer stamps `savedAt`, which keeps gameplay output reproducible.
	var out := {
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
		"factions": factions.duplicate(true),
	}
	if Hand.declared(hand_spec):
		# Only a package that dealt a hand carries the piles, so a story that
		# never asked for one keeps the payload it always had (TC-DET-001).
		out["hand"] = hand.duplicate()
		out["deck"] = deck.duplicate()
		out["discard"] = discard.duplicate()
	if assembly.size() > 1:
		# A run made of several packages has to come back as the same set, or a
		# resumed save would quietly lose the addition it was playing with
		# (REQ-041).
		out["assembly"] = assembly.duplicate()
	return out


func restore_factions(saved: Variant) -> void:
	## The faction map is part of the run once a rule can move it (REQ-032). A
	## payload without one keeps the map the package declared.
	if not (saved is Dictionary):
		return
	var parsed: Dictionary = saved
	if not (parsed.get("entities", null) is Dictionary):
		return
	factions = parsed.duplicate(true)


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
