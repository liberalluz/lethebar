class_name SaveBackend
extends RefCounted
## Storage seam for everything that must survive a reload (SDD §7.4).
##
## The stores only talk to this interface, so slot layout, the schema gate and
## the package round-trip are tested headlessly against a memory backend while a
## browser backend can be added without touching them. A backend stores opaque
## text under a key; it parses, validates and migrates nothing.


func write(_key: String, _text: String) -> bool:
	## Returns whether the write happened, so a caller never reports a save that
	## was not written (SDD §7.4).
	return false


func read(_key: String) -> String:
	return ""


func has(key: String) -> bool:
	return read(key) != ""


func erase(_key: String) -> bool:
	return false


func keys() -> Array:
	return []
