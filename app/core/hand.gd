class_name Hand
extends RefCounted
## A hand of cards a package declares (REQ-036, engine-bricks §6).
##
## The engine owns the three piles because they are state a save has to carry.
## There is no shuffle here: the deck order is the declared order, so the same
## save always draws the same cards.

const CAPABILITY := "cards.hand@1"
const DEFAULT_SIZE := 5
const DEFAULT_DRAW := 1
## The three piles travel in the save under these keys.
const KEYS := ["hand", "deck", "discard"]


static func defines(raw: Dictionary) -> Dictionary:
	## The hand may sit under its own key or beside the cards; both read alike.
	var params: Dictionary = raw
	if raw.get("hand", null) is Dictionary:
		params = raw["hand"]
	var size := int(params.get("size", DEFAULT_SIZE))
	var draw := int(params.get("draw_per_turn", DEFAULT_DRAW))
	var cards: Dictionary = {}
	var listed: Variant = raw.get("cards", [])
	if listed is Array:
		for card in listed:
			if card is Dictionary and card.has("id"):
				cards[String(card["id"])] = card
	var deck: Array = []
	var order: Variant = raw.get("deck", [])
	if order is Array:
		for id in order:
			if id is String:
				deck.append(id)
	return {
		"size": maxi(size, 1),
		"draw": maxi(draw, 0),
		"reshuffle": bool(raw.get("reshuffle", true)),
		"cards": cards,
		"deck": deck,
	}


static func declared(spec: Dictionary) -> bool:
	return not (spec.get("deck", []) as Array).is_empty()


static func card(spec: Dictionary, card_id: String) -> Dictionary:
	var cards: Dictionary = spec.get("cards", {})
	var entry: Variant = cards.get(card_id, null)
	return entry if entry is Dictionary else {}


static func deals(spec: Dictionary) -> Dictionary:
	## The piles as a run starts: the hand comes off the front of the deck.
	var piles := {"hand": [], "deck": (spec.get("deck", []) as Array).duplicate(), "discard": []}
	return draw_into(piles, spec, int(spec.get("size", 0)))


static func draw_into(piles: Dictionary, spec: Dictionary, count: int) -> Dictionary:
	## Takes up to `count` cards off the deck; the discard pile goes back under it
	## in play order when the package asks for it. Still no shuffle.
	var out := {
		"hand": (piles.get("hand", []) as Array).duplicate(),
		"deck": (piles.get("deck", []) as Array).duplicate(),
		"discard": (piles.get("discard", []) as Array).duplicate(),
	}
	var reshuffle := bool(spec.get("reshuffle", true))
	var taken := 0
	while taken < count:
		if (out["deck"] as Array).is_empty():
			if not reshuffle or (out["discard"] as Array).is_empty():
				break
			out["deck"] = (out["discard"] as Array).duplicate()
			out["discard"] = []
		var top: Variant = (out["deck"] as Array).pop_front()
		(out["hand"] as Array).append(String(top))
		taken += 1
	return out


static func take(piles: Dictionary, card_id: String) -> Dictionary:
	## One card from the hand onto the discard pile; a card never dealt returns {}.
	var out := {
		"hand": (piles.get("hand", []) as Array).duplicate(),
		"deck": (piles.get("deck", []) as Array).duplicate(),
		"discard": (piles.get("discard", []) as Array).duplicate(),
	}
	var at: int = (out["hand"] as Array).find(card_id)
	if at < 0:
		return {}
	(out["hand"] as Array).remove_at(at)
	(out["discard"] as Array).append(card_id)
	return out


static func icon_of(spec: Dictionary, card_id: String) -> String:
	## The picture a card names, or an empty string when it names none. The
	## manifest decides whether that path exists; the hand only reports it.
	var entry := card(spec, card_id)
	if not entry.has("icon"):
		return ""
	return String(entry.get("icon", ""))


static func label_of(spec: Dictionary, card_id: String) -> String:
	var entry := card(spec, card_id)
	return String(entry.get("label", card_id))
