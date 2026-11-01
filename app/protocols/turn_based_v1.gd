class_name TurnBasedV1
extends RefCounted
## `turn_based@1` — the segment is a sequence of rounds (SDD §5.2, §10.1).
##
## A round is one node: the choices on that node are the intents available in
## that round, resolving one intent ends the round, and the node the choice
## points at opens the next round. The round number is derived from the nodes the
## session has already visited, so the protocol carries no state of its own and
## the save payload keeps the shape SDD §7.2 defines.

const PROTOCOL_ID := "turn_based@1"


func start(session) -> Dictionary:
	return _with_round(session, session.goto(String(session.entry_node)))


func advance(session, intent: Dictionary) -> Dictionary:
	var offered: Array = session.choices()
	var index := int(intent.get("choice", -1))
	if index < 0 or index >= offered.size():
		session.reject("S-03", "intent %d is outside the round" % index)
		return _with_round(session, session.view())
	var choice: Dictionary = offered[index]
	session.apply_effects(choice.get("effects", []))
	return _with_round(session, session.goto(String(choice.get("next", ""))))


func evaluate(session) -> Dictionary:
	## The session applies its mechanic rules on every node change (SDD §6.2), so
	## evaluation here is reading the state that is already current.
	return _with_round(session, session.view())


func snapshot(session) -> Dictionary:
	return session.snapshot()


static func round_of(session) -> int:
	## Rounds played so far. The entry node is round 1, and an ending node is not
	## a round of its own, so a finished segment reports the round it ended in.
	var played: int = session.visited.size()
	if session.finished and played > 1:
		played -= 1
	return played


func _with_round(session, view: Dictionary) -> Dictionary:
	## The round is readout only: it is added to the view, never to `state` or to
	## the snapshot, so a plugin's own rule table cannot collide with it.
	var out: Dictionary = view.duplicate(true)
	out["round"] = round_of(session)
	return out
