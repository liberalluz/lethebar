class_name Relations
extends RefCounted

## Directed relations between relations (engine-bricks §7). The numbers and the
## names "ally" and "hostile" come from the package: the engine never decides
## what close means, and it never assumes a pair is symmetric.

const ID_PATTERN := "^[a-z][a-z0-9_]*$"

static var _id_re: RegEx


static func _id_pattern() -> RegEx:
	if _id_re == null:
		_id_re = RegEx.new()
		_id_re.compile(ID_PATTERN)
	return _id_re


static func defines(relations: Variant) -> Dictionary:
	## The parsed file: thresholds, entities by id, and the order they were
	## declared in (the order the interface prints them).
	var out := {"thresholds": {}, "entities": {}, "order": []}
	if not (relations is Dictionary):
		return out
	if relations.get("thresholds", null) is Dictionary:
		out["thresholds"] = relations["thresholds"].duplicate(true)
	if relations.get("entities", null) is Array:
		for entity in relations["entities"]:
			if entity is Dictionary and entity.has("id"):
				var id := String(entity["id"])
				out["entities"][id] = entity
				out["order"].append(id)
	return out


static func declares(parsed: Dictionary) -> bool:
	return not (parsed.get("entities", {}) as Dictionary).is_empty()


static func value(parsed: Dictionary, from_id: String, to_id: String) -> float:
	## What `from_id` feels about `to_id`, and only that direction. A pair the
	## package leaves out reads as zero.
	var entities: Dictionary = parsed.get("entities", {})
	if not entities.has(from_id):
		return 0.0
	var relations: Variant = (entities[from_id] as Dictionary).get("relations", null)
	if relations is Dictionary and relations.has(to_id):
		var raw: Variant = relations[to_id]
		if raw is int or raw is float:
			return float(raw)
	return 0.0


static func state(parsed: Dictionary, from_id: String, to_id: String) -> String:
	## The first declared threshold the value crosses, or "" when none does. The
	## engine carries no state names of its own.
	var number := value(parsed, from_id, to_id)
	var thresholds: Dictionary = parsed.get("thresholds", {})
	for name in thresholds:
		var edge: Variant = thresholds[name]
		if not (edge is int or edge is float):
			continue
		var bound := float(edge)
		if (bound >= 0.0 and number >= bound) or (bound < 0.0 and number <= bound):
			return String(name)
	return ""


static func label(parsed: Dictionary, entity_id: String) -> String:
	var entities: Dictionary = parsed.get("entities", {})
	if not entities.has(entity_id):
		return entity_id
	var entity: Dictionary = entities[entity_id]
	return String(entity.get("label", entity_id))


static func referenced_states(parsed: Dictionary) -> Array:
	## Every `{"relation": id, "state": name}` a condition could ask for is not
	## visible here; what is visible is which state names exist at all, which is
	## what V-20 needs to refuse a name the package never declared.
	var out: Array = []
	var thresholds: Dictionary = parsed.get("thresholds", {})
	for name in thresholds:
		out.append(String(name))
	return out


static func problems(relations: Variant) -> Array:
	## Returns `{message, fatal}` entries: a broken entity map is fatal (V-20), a
	## pair that is not symmetric is only a warning (W-02), because the engine
	## never rewrites what a package meant.
	var out: Array = []
	if relations == null:
		return out
	if not (relations is Dictionary):
		out.append({"message": "data/relations.json must be an object", "fatal": true})
		return out
	if relations.get("thresholds", null) != null and not (relations["thresholds"] is Dictionary):
		out.append({"message": "thresholds must be an object", "fatal": true})
	if relations.get("entities", null) == null:
		out.append({"message": "data/relations.json must declare entities", "fatal": true})
		return out
	if not (relations["entities"] is Array):
		out.append({"message": "entities must be an array", "fatal": true})
		return out
	var seen: Array = []
	for entity in relations["entities"]:
		if not (entity is Dictionary):
			out.append({"message": "an entity must be an object", "fatal": true})
			continue
		var entity_id := String(entity.get("id", ""))
		if not _id_pattern().search(entity_id):
			out.append({
				"message": "entity id %s does not match %s" % [entity_id, ID_PATTERN],
				"fatal": true,
			})
		elif seen.has(entity_id):
			out.append({"message": "entity id %s is declared twice" % entity_id, "fatal": true})
		else:
			seen.append(entity_id)
		var edges: Variant = entity.get("relations", null)
		if edges == null:
			continue
		if not (edges is Dictionary):
			out.append({
				"message": "entity %s has relations that are not an object" % entity_id,
				"fatal": true,
			})
			continue
		for other in edges:
			if not seen.has(String(other)) and not _declared_later(relations["entities"], String(other)):
				out.append({
					"message": "entity %s points at %s, which is not declared" % [entity_id, other],
					"fatal": true,
				})
			var raw: Variant = edges[other]
			if not (raw is int or raw is float):
				out.append({
					"message": "entity %s has a non-number for %s" % [entity_id, other],
					"fatal": true,
				})
	if relations.get("thresholds", null) is Dictionary:
		for name in relations["thresholds"]:
			var edge: Variant = relations["thresholds"][name]
			if not (edge is int or edge is float):
				out.append({
					"message": "threshold %s is not a number" % name,
					"fatal": true,
				})
	for entity in relations["entities"]:
		if not (entity is Dictionary):
			continue
		var entity_id := String(entity.get("id", ""))
		var edges: Variant = entity.get("relations", null)
		if not (edges is Dictionary):
			continue
		for other in edges:
			var back: Variant = _raw(relations["entities"], String(other), entity_id)
			var forward: Variant = edges[other]
			if back == null:
				continue
			if float(forward) != float(back):
				out.append({
					"message": "%s and %s disagree: %s vs %s"
					% [entity_id, other, float(forward), float(back)],
					"fatal": false,
				})
	return out


static func _declared_later(entities: Array, entity_id: String) -> bool:
	for entity in entities:
		if entity is Dictionary and String(entity.get("id", "")) == entity_id:
			return true
	return false


static func _raw(entities: Array, from_id: String, to_id: String) -> Variant:
	for entity in entities:
		if not (entity is Dictionary) or String(entity.get("id", "")) != from_id:
			continue
		var relations: Variant = entity.get("relations", null)
		if relations is Dictionary and relations.has(to_id):
			var raw: Variant = relations[to_id]
			if raw is int or raw is float:
				return float(raw)
	return null
