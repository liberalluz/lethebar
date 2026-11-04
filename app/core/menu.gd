class_name Menu
extends RefCounted

## The action menu (engine-bricks §3). The engine renders the menu and marks an
## action unusable rather than hiding it: a disabled action is a state the player
## can read, not an error.

const ID_PATTERN := "^[a-z][a-z0-9_]*$"
const LIMITS := ["per_turn", "per_run"]

static var _id_re: RegEx = RegEx.create_from_string(ID_PATTERN)


static func list(data: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = data.get("actions", null)
	if raw is Array:
		for action in raw:
			if action is Dictionary:
				out.append(action)
	return out


static func by_id(actions: Array, action_id: String) -> Dictionary:
	for action in actions:
		if String(action.get("id", "")) == action_id:
			return action
	return {}


static func availability(action: Dictionary, session: Session) -> Dictionary:
	## Every `requires` entry must hold. The first failing one is returned so the
	## interface can say what stands in the way instead of only greying the label.
	var requires: Variant = action.get("requires", null)
	if requires is Array:
		for condition in requires:
			if condition is Dictionary and not _holds(condition, session.state):
				return {"enabled": false, "reason": _reason(condition)}
	if limit_reached(action, session):
		return {"enabled": false, "reason": "used up"}
	return {"enabled": true, "reason": ""}


static func limit_reached(action: Dictionary, session: Session) -> bool:
	var limit: Variant = action.get("limit", null)
	if not limit is Dictionary:
		return false
	var action_id := String(action.get("id", ""))
	var used: Dictionary = session.used.get(action_id, {})
	if limit.has("per_run") and int(used.get("per_run", 0)) >= int(limit["per_run"]):
		return true
	if limit.has("per_turn") and int(used.get("turn", -1)) == session.turn and int(used.get("per_turn", 0)) >= int(limit["per_turn"]):
		return true
	return false


static func record_use(action: Dictionary, session: Session) -> void:
	var action_id := String(action.get("id", ""))
	var used: Dictionary = session.used.get(action_id, {})
	used["per_run"] = int(used.get("per_run", 0)) + 1
	if int(used.get("turn", -1)) != session.turn:
		used["turn"] = session.turn
		used["per_turn"] = 0
	used["per_turn"] = int(used.get("per_turn", 0)) + 1
	session.used[action_id] = used


static func problems(actions: Array) -> Array:
	## V-16: a duplicate id, an action with no effects, a limit the engine does not
	## count. Costs are effects that happen to be negative; both are checked.
	var out: Array = []
	var seen: Array = []
	for action in actions:
		var action_id := String(action.get("id", ""))
		if _id_re.search(action_id) == null:
			out.append("action id %s does not match %s" % [action_id, ID_PATTERN])
		if seen.has(action_id):
			out.append("action id %s appears twice" % action_id)
		seen.append(action_id)
		var effects: Variant = action.get("effects", null)
		if not effects is Array or (effects as Array).is_empty():
			out.append("action %s has no effects" % action_id)
		var limit: Variant = action.get("limit", null)
		if limit is Dictionary:
			for key in limit:
				if not LIMITS.has(String(key)):
					out.append("action %s limits %s, which the engine never counts" % [action_id, String(key)])
				elif int(limit[key]) < 1:
					out.append("action %s limits %s to %d" % [action_id, String(key), int(limit[key])])
	return out


static func referenced_keys(actions: Array) -> Array:
	## Every resource an action touches, so the validator can check them against
	## the ledger alongside the rules (V-14).
	var out: Array = []
	for action in actions:
		for section in ["costs", "effects"]:
			var table: Variant = action.get(section, null)
			if table is Dictionary:
				for key in table:
					if not out.has(String(key)):
						out.append(String(key))
		var requires: Variant = action.get("requires", null)
		if requires is Array:
			for condition in requires:
				if condition is Dictionary and not out.has(String(condition.get("key", ""))):
					out.append(String(condition.get("key", "")))
	return out


static func _holds(condition: Dictionary, state: Dictionary) -> bool:
	var key := String(condition.get("key", ""))
	var op := String(condition.get("op", ""))
	var value := float(condition.get("value", 0.0))
	var current := float(state.get(key, 0.0))
	match op:
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


static func _reason(condition: Dictionary) -> String:
	var key := String(condition.get("key", ""))
	var op := String(condition.get("op", ""))
	var value := float(condition.get("value", 0.0))
	var word := {"gte": "at least", "lte": "at most", "gt": "more than", "lt": "less than", "eq": "exactly"}
	return "%s must be %s %s" % [key, String(word.get(op, op)), _number(value)]


static func _number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return "%.1f" % value
