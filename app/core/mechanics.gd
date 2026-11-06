class_name Mechanics
extends RefCounted
## Declarative rule application (SDD §3.3, §6.2).
##
## A rule is `{"when": <condition>, "set": {key: <change>}}`, where a condition is
## `{"key": ..., "op": eq|ne|gt|gte|lt|lte, "value": ...}` (or a list of those,
## matched with AND) and a change is a plain value, `{"value": v}` or
## `{"add": n}`. There is deliberately no expression language: a `when` written
## as a string is reported as bad plugin data instead of being evaluated.

const OPS := ["eq", "ne", "gt", "gte", "lt", "lte"]


static func apply(rules: Array, state: Dictionary, scope: Dictionary = {}) -> Dictionary:
	## `scope` is where the engine puts numbers a rule may read but the package
	## does not own — today only the tick (engine-bricks §8).
	return _run(rules, state, scope)


static func apply_effects(effects: Array, state: Dictionary) -> Dictionary:
	## Choice effects use the same `set` shape as rules, without a condition.
	var ops: Array = []
	for effect in effects:
		if effect is Dictionary:
			ops.append({"set": effect})
		else:
			ops.append({})
	return _run(ops, state)


static func _run(ops: Array, state: Dictionary, scope: Dictionary = {}) -> Dictionary:
	var out := state.duplicate(true)
	var warnings: Array = []
	var relations: Array = []
	for item in ops:
		var rule: Dictionary = item if item is Dictionary else {}
		if not rule.has("set"):
			warnings.append(_warning("M-01", "rule without a set clause"))
			continue
		if rule.has("when") and not _matches(rule["when"], out, warnings, scope):
			continue
		_apply_set(rule["set"], out, warnings)
		for change in _relation_changes(rule):
			relations.append(change)
	return {"state": out, "warnings": warnings, "relations": relations}


static func _relation_changes(rule: Dictionary) -> Array:
	## A rule may move the way one entity feels about another. The engine never
	## applies the move itself: it hands the changes back so the session, which
	## owns the faction map, stays the only writer (REQ-032).
	var raw: Variant = rule.get("relations", null)
	if not (raw is Array):
		return []
	var out: Array = []
	for entry in raw:
		if not (entry is Dictionary):
			continue
		var from_id := String(entry.get("from", ""))
		var to_id := String(entry.get("to", ""))
		if from_id == "" or to_id == "":
			continue
		if entry.has("add"):
			out.append({"from": from_id, "to": to_id, "add": _number(entry["add"])})
		elif entry.has("value"):
			out.append({"from": from_id, "to": to_id, "value": _number(entry["value"])})
	return out


static func _matches(when: Variant, state: Dictionary, warnings: Array, scope: Dictionary = {}) -> bool:
	if when is Array:
		for condition in when:
			if not _matches(condition, state, warnings, scope):
				return false
		return true
	if not when is Dictionary:
		warnings.append(_warning("M-02", "a when clause must be an object, not %s" % typeof(when)))
		return false
	var condition: Dictionary = when
	if not condition.has("key"):
		warnings.append(_warning("M-02", "a when clause needs a key"))
		return false
	var op := String(condition.get("op", "eq"))
	if not OPS.has(op):
		warnings.append(_warning("M-02", "unknown comparison %s" % op))
		return false
	var key := String(condition["key"])
	var left: Variant = scope[key] if scope.has(key) else state.get(key, null)
	var right: Variant = condition.get("value", null)
	return _compare(left, right, op)


static func _compare(left: Variant, right: Variant, op: String) -> bool:
	if typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT]:
		var a := float(left)
		var b := float(right)
		match op:
			"eq": return a == b
			"ne": return a != b
			"gt": return a > b
			"gte": return a >= b
			"lt": return a < b
			"lte": return a <= b
	var same: bool = left == right
	return same if op == "eq" else (not same if op == "ne" else false)


static func _apply_set(clause: Variant, out: Dictionary, warnings: Array) -> void:
	if not clause is Dictionary:
		warnings.append(_warning("M-03", "a set clause must be an object"))
		return
	for key in clause:
		var change: Variant = clause[key]
		var name := String(key)
		if change is Dictionary:
			if change.has("add"):
				out[name] = _number(out.get(name, 0)) + _number(change["add"])
			elif change.has("value"):
				out[name] = change["value"]
			else:
				warnings.append(_warning("M-03", "%s needs add or value" % name))
		else:
			out[name] = change


static func _number(value: Variant) -> float:
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return float(value)
	return 0.0


static func _warning(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}
