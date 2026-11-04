class_name Ledger
extends RefCounted
## The state ledger (engine-bricks §1): `data/state.json` declares the numbers a
## package plays with, their starting value and their bounds.
##
## Every value is a number. `min` and `max` are inclusive, and a write outside
## them is clamped rather than refused — a story should never stop because a
## number ran out. A resource may carry `labels` (`{"2": "名动诸侯"}`): the value
## stays numeric and the interface prints the label when it knows the number.

const DEFAULT_MIN := 0.0
const DEFAULT_MAX := 999999.0
const ID_PATTERN := "^[a-z][a-z0-9_]*$"


static func definitions(ledger: Variant) -> Dictionary:
	## id -> {label, init, min, max, labels}, in file order.
	var out: Dictionary = {}
	if not (ledger is Dictionary):
		return out
	var resources: Variant = ledger.get("resources", [])
	if not (resources is Array):
		return out
	for item in resources:
		if not (item is Dictionary):
			continue
		var id := String(item.get("id", ""))
		if id.is_empty() or out.has(id):
			continue
		out[id] = {
			"label": String(item.get("label", id)),
			"init": _number(item.get("init", 0.0), 0.0),
			"min": _number(item.get("min", DEFAULT_MIN), DEFAULT_MIN),
			"max": _number(item.get("max", DEFAULT_MAX), DEFAULT_MAX),
			"labels": item.get("labels", {}) if item.get("labels") is Dictionary else {},
		}
	return out


static func initial(defs: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for id in defs:
		out[id] = defs[id]["init"]
	return out


static func clamp_value(defs: Dictionary, id: String, value: float) -> float:
	if not defs.has(id):
		return value
	var low: float = defs[id]["min"]
	var high: float = defs[id]["max"]
	return clampf(value, low, high)


static func label_for(defs: Dictionary, id: String, value: float) -> String:
	if not defs.has(id):
		return ""
	var labels: Dictionary = defs[id]["labels"]
	var key := _label_key(value)
	if labels.has(key):
		return String(labels[key])
	return ""


static func problems(ledger: Variant) -> Array:
	## What §1 says a ledger may not be. Each entry names the resource.
	var issues: Array = []
	if not (ledger is Dictionary):
		issues.append("state.json must be an object")
		return issues
	var resources: Variant = ledger.get("resources", null)
	if not (resources is Array):
		issues.append("state.json must carry a resources array")
		return issues
	var seen: Dictionary = {}
	var pattern := RegEx.new()
	pattern.compile(ID_PATTERN)
	for item in resources:
		if not (item is Dictionary):
			issues.append("every resource must be an object")
			continue
		var id := String(item.get("id", ""))
		if id.is_empty() or pattern.search(id) == null:
			issues.append("resource id %s must match %s" % [id, ID_PATTERN])
			continue
		if seen.has(id):
			issues.append("resource %s is declared twice" % id)
		seen[id] = true
		for field in ["init", "min", "max"]:
			if item.has(field) and not _is_number(item[field]):
				issues.append("resource %s field %s must be a number" % [id, field])
		if _is_number(item.get("min", DEFAULT_MIN)) and _is_number(item.get("max", DEFAULT_MAX)):
			if float(item.get("min", DEFAULT_MIN)) > float(item.get("max", DEFAULT_MAX)):
				issues.append("resource %s has min above max" % id)
		var labels: Variant = item.get("labels", {})
		if not (labels is Dictionary):
			issues.append("resource %s labels must be an object" % id)
		elif not labels.is_empty():
			for key in labels:
				if not String(key).is_valid_int() and not String(key).is_valid_float():
					issues.append("resource %s label key %s must be a number" % [id, key])
				if not (labels[key] is String):
					issues.append("resource %s label %s must be text" % [id, key])
	return issues


static func _label_key(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(value)


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _number(value: Variant, fallback: float) -> float:
	if value is int or value is float:
		return float(value)
	return fallback
