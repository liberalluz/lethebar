class_name Checks
extends RefCounted

## Checks (engine-bricks §5). One check answers yes or no and keeps the numbers
## that decided it, because a player who is told only "no" cannot learn anything
## from the loss. Rolls come from the session RNG, so the same seed and the same
## choices produce the same outcomes (TC-DET-001).
##
## There is no free-form probability expression: `roll`, `target` and `bonus` are
## the whole surface.

const DEFAULT_DICE := 1
const DEFAULT_SIDES := 100


static func list(data: Dictionary) -> Array:
	var out: Array = []
	var raw: Variant = data.get("checks", null)
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:
				out.append(entry)
	return out


static func by_id(checks: Array, check_id: String) -> Dictionary:
	for entry in checks:
		if String(entry.get("id", "")) == check_id:
			return entry
	return {}


static func resolve(session: Session, check_id: String) -> Dictionary:
	## Rolls, adds the bonus the package declared, compares with the target, and
	## stores `{roll, bonus, total, target, passed}` under `state.checks.<id>`.
	var check := by_id(session.checks, check_id)
	if check.is_empty():
		session.reject("S-03", "no check named %s" % check_id)
		return {"ok": false, "message": "no check named %s" % check_id}
	var roll_spec: Variant = check.get("roll", {})
	var dice := DEFAULT_DICE
	var sides := DEFAULT_SIDES
	if roll_spec is Dictionary:
		dice = int(roll_spec.get("dice", DEFAULT_DICE))
		sides = int(roll_spec.get("sides", DEFAULT_SIDES))
	var roll := 0
	for _i in maxi(dice, 1):
		session.step_rng()
		roll += 1 + int(session.rng % maxi(sides, 1))
	var bonus := 0
	var bonus_spec: Variant = check.get("bonus", null)
	if bonus_spec is Dictionary:
		var key := String(bonus_spec.get("key", ""))
		var scale := float(bonus_spec.get("scale", 1.0))
		bonus = int(floorf(float(session.state.get(key, 0.0)) * scale))
	var total := roll + bonus
	var target := int(check.get("target", 0))
	var passed := total >= target
	if not session.state.has("checks") or not session.state["checks"] is Dictionary:
		session.state["checks"] = {}
	session.state["checks"][check_id] = {
		"roll": roll,
		"bonus": bonus,
		"total": total,
		"target": target,
		"passed": passed,
	}
	return {"ok": true, "passed": passed, "roll": roll, "bonus": bonus, "total": total, "target": target}


static func problems(checks: Array) -> Array:
	## V-18: a die with fewer than two faces cannot decide anything, and a target
	## outside the dice range is either always true or always false.
	var out: Array = []
	var seen: Array = []
	for check in checks:
		var check_id := String(check.get("id", ""))
		if check_id == "":
			out.append("a check has no id")
		elif seen.has(check_id):
			out.append("check id %s appears twice" % check_id)
		seen.append(check_id)
		var roll_spec: Variant = check.get("roll", {})
		var dice := DEFAULT_DICE
		var sides := DEFAULT_SIDES
		if roll_spec is Dictionary:
			dice = int(roll_spec.get("dice", DEFAULT_DICE))
			sides = int(roll_spec.get("sides", DEFAULT_SIDES))
		if dice < 1:
			out.append("check %s rolls %d dice" % [check_id, dice])
		if sides < 2:
			out.append("check %s rolls a die with %d sides" % [check_id, sides])
		var target := int(check.get("target", 0))
		if target < dice or target > dice * sides:
			out.append("check %s targets %d, outside %d..%d" % [check_id, target, dice, dice * sides])
		var bonus_spec: Variant = check.get("bonus", null)
		if bonus_spec is Dictionary and String(bonus_spec.get("key", "")) == "":
			out.append("check %s has a bonus with no resource" % check_id)
	return out
