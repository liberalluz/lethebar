class_name MemoryBackend
extends SaveBackend
## Process-lifetime storage: what the headless suite uses, and what a platform
## with no persistent backend falls back to.
##
## The map is `static` on purpose: a fresh instance sees what a previous one
## wrote, which is how a page reload behaves, so a test can build a second store
## over the same data and call that a reload.

static var _data: Dictionary = {}
static var refuse_writes := false


static func reset() -> void:
	_data.clear()
	refuse_writes = false


func write(key: String, text: String) -> bool:
	if refuse_writes:
		return false
	_data[key] = text
	return true


func read(key: String) -> String:
	return String(_data.get(key, ""))


func erase(key: String) -> bool:
	return _data.erase(key)


func keys() -> Array:
	var out: Array = _data.keys()
	out.sort()
	return out
