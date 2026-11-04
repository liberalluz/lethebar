class_name Phases
extends RefCounted

## The phase machine (engine-bricks §4). The turn number is the only bookkeeping:
## a rank is read from it, so a save restored at turn 13 shows the rank for turn
## 13 without storing anything extra.

const DEFAULT_TURNS := 24


static func defines(raw: Dictionary) -> Dictionary:
	var out := {"turns": DEFAULT_TURNS, "ranks": [], "fail": []}
	if raw.get("turns", null) is int or raw.get("turns", null) is float:
		out["turns"] = int(raw["turns"])
	if raw.get("ranks", null) is Array:
		out["ranks"] = raw["ranks"]
	if raw.get("fail", null) is Array:
		out["fail"] = raw["fail"]
	return out


static func declares(raw: Dictionary) -> bool:
	return raw.has("turns") or raw.has("ranks") or raw.has("fail")


static func rank(defs: Dictionary, turn: int) -> String:
	## The last rank whose `at` has been reached; before the first one there is no
	## rank to show.
	var title := ""
	for entry in defs.get("ranks", []):
		if entry is Dictionary and turn >= int(entry.get("at", 0)):
			title = String(entry.get("title", ""))
	return title


static func failure(defs: Dictionary, state: Dictionary) -> Dictionary:
	## The first failing entry wins and ends the run; the reason is shown to the
	## player, which is why an empty reason is refused at install time (V-17).
	for entry in defs.get("fail", []):
		if not entry is Dictionary:
			continue
		var condition: Variant = entry.get("when", null)
		if condition is Dictionary and _holds(condition, state):
			return entry
	return {}


static func problems(raw: Dictionary) -> Array:
	## V-17: a run that cannot be played to its end, a rank nobody can reach, a
	## failure with nothing to tell the player.
	var out: Array = []
	var turns := DEFAULT_TURNS
	if raw.get("turns", null) != null:
		var value: Variant = raw["turns"]
		if not (value is int or value is float):
			out.append("turns is not a number")
		elif int(value) < 1:
			out.append("turns is %d" % int(value))
		else:
			turns = int(value)
	var ranks: Variant = raw.get("ranks", [])
	if ranks is Array:
		var previous := 0
		for entry in ranks:
			if not entry is Dictionary:
				out.append("a rank is not an object")
				continue
			var at := int(entry.get("at", 0))
			if at < 1 or at > turns:
				out.append("rank at %d is outside 1..%d" % [at, turns])
			if at <= previous:
				out.append("rank at %d does not come after %d" % [at, previous])
			previous = at
			if String(entry.get("title", "")) == "":
				out.append("rank at %d has no title" % at)
	var fail: Variant = raw.get("fail", [])
	if fail is Array:
		for entry in fail:
			if not entry is Dictionary:
				out.append("a failure is not an object")
				continue
			if String(entry.get("reason", "")) == "":
				out.append("a failure carries no reason")
			if not entry.get("when", null) is Dictionary:
				out.append("a failure carries no condition")
	return out


static func _holds(condition: Dictionary, state: Dictionary) -> bool:
	var key := String(condition.get("key", ""))
	var value := float(condition.get("value", 0.0))
	var current := float(state.get(key, 0.0))
	match String(condition.get("op", "")):
		"gte":
			return current >= value
		"lte":
			return current <= value
		"gt":
			return current > value
		"lt":
			return current < value
		"eq":
			return is_equal_approx(current, value)
	return false
