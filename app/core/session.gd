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
	session.state = {}
	session.visited = []
	session.warnings = []
	session.finished = false
	session.current = ""
	session.nodes = {}
	session.mechanics = {}
	var data: Dictionary = entry.get("data", {})
	for node in data.get("nodes", []):
		if node is Dictionary and node.has("id"):
			session.nodes[String(node["id"])] = node
	if data.get("mechanics", null) is Dictionary:
		session.mechanics = data["mechanics"]
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
	_step_rng()
	apply_rules()
	var node: Dictionary = nodes[current]
	finished = choices_of(node).is_empty()
	return view()


func apply_rules() -> void:
	var rules: Array = []
	if mechanics.get("rules", null) is Array:
		rules = mechanics["rules"]
	var result := Mechanics.apply(rules, state)
	state = result["state"]
	_absorb(result["warnings"])


func apply_effects(effects: Array) -> void:
	var result := Mechanics.apply_effects(effects, state)
	state = result["state"]
	_absorb(result["warnings"])


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
		"finished": finished,
		"warnings": warnings.duplicate(true),
	}
	if declares("progress"):
		out["progress"] = {"steps": visited.size(), "nodes": nodes.size()}
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
