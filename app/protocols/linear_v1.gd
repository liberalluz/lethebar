class_name LinearV1
extends RefCounted
## `linear@1` — a node graph where every choice moves straight to the next node
## (SDD §5.2). This is the whole protocol: no rounds, no turn order, no timers.

const PROTOCOL_ID := "linear@1"


func start(session) -> Dictionary:
	return session.goto(String(session.entry_node))


func advance(session, intent: Dictionary) -> Dictionary:
	var offered: Array = session.choices()
	var index := int(intent.get("choice", -1))
	if index < 0 or index >= offered.size():
		session.reject("S-03", "choice %d is outside the current node" % index)
		return session.view()
	var choice: Dictionary = offered[index]
	session.apply_effects(choice.get("effects", []))
	return session.goto(String(choice.get("next", "")))


func evaluate(session) -> Dictionary:
	## The session applies its mechanic rules on every node change (SDD §6.2), so
	## evaluation here is reading the state that is already current.
	return session.view()


func snapshot(session) -> Dictionary:
	return session.snapshot()
