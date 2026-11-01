class_name ProtocolRegistry
extends RefCounted
## Maps `protocol@version` to the code that plays it (SDD §5.2).
##
## This table is the single source of truth for `V-06`: a package whose protocol
## is not listed here is rejected at import, which is what makes the promise
## "the engine does not know gameplay, only protocols" checkable.

const IMPLEMENTATIONS := {
	"linear@1": preload("res://app/protocols/linear_v1.gd"),
	"turn_based@1": preload("res://app/protocols/turn_based_v1.gd"),
}


static func known_ids() -> Array:
	var ids: Array = IMPLEMENTATIONS.keys()
	ids.sort()
	return ids


static func supports(protocol_id: String) -> bool:
	return IMPLEMENTATIONS.has(protocol_id)


static func implementation(protocol_id: String) -> Object:
	if not IMPLEMENTATIONS.has(protocol_id):
		return null
	return IMPLEMENTATIONS[protocol_id].new()
