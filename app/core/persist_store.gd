class_name PersistStore
extends RefCounted
## B112: the memory a package keeps across runs (`persist@1`). It is a small
## typed table, declared in the manifest and written by effects, that lives
## outside the save snapshot: the run can be replayed, the player cannot.
##
## Stored under `memory:<bundle id>` so it survives a reload of the page and is
## not erased when a pack is removed (saves are not erased either).

const KEY_PREFIX := "memory:"
const MAX_KEYS := 32
const MAX_BYTES := 4096
const MAX_DEPTH := 2
const CODE_SHAPE := "V-47"

var backend: SaveBackend
var plugin_id: String
var values: Dictionary = {}
var error: String = ""


func _init(store_backend: SaveBackend, id: String) -> void:
	backend = store_backend
	plugin_id = id


func key() -> String:
	return KEY_PREFIX + plugin_id


static func defaults(definition: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (definition is Dictionary):
		return out
	for name in definition:
		out[String(name)] = _coerce(_copy((definition as Dictionary)[name]))
	return out


## Declares the table. Returns an empty string on success, or a code when the
## declaration itself is refused (the validator normally catches this first).
func declare(definition: Variant) -> String:
	if definition == null:
		return ""
	if not (definition is Dictionary):
		error = CODE_SHAPE
		return error
	var declared: Dictionary = definition
	if values.size() + declared.size() > MAX_KEYS:
		error = CODE_SHAPE
		return error
	for name in declared:
		var id := String(name)
		if not _valid_id(id):
			error = CODE_SHAPE
			return error
		var value: Variant = declared[name]
		if not _valid_value(value):
			error = CODE_SHAPE
			return error
		if not values.has(id):
			values[id] = _coerce(_copy(value))
	return ""


## Reads the stored table, keeping only declared keys of the declared type.
func load() -> void:
	if backend == null:
		return
	var text := String(backend.read(key()))
	if text == "":
		_save()
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	for name in values:
		var id := String(name)
		if not (parsed as Dictionary).has(id):
			continue
		var value: Variant = (parsed as Dictionary)[id]
		if _same_type(values[id], value):
			values[id] = _coerce(value)


## Applies one write: a plain value, `{"value": v}` or `{"add": n}`.
func set_value(key_name: String, change: Variant) -> Dictionary:
	var id := key_name
	if not values.has(id):
		return {"ok": false, "code": CODE_SHAPE, "message": "persist.%s is not declared" % id}
	var current: Variant = values[id]
	var value: Variant = change
	if change is Dictionary and (change as Dictionary).has("add"):
		if not (current is int or current is float):
			return {"ok": false, "code": CODE_SHAPE, "message": "persist.%s is not a number" % id}
		value = float(current) + float((change as Dictionary)["add"])
	elif change is Dictionary and (change as Dictionary).has("value"):
		value = (change as Dictionary)["value"]
	if not _same_type(current, value):
		return {"ok": false, "code": CODE_SHAPE, "message": "persist.%s keeps a %s" % [id, type_string(typeof(current))]}
	values[id] = _coerce(value)
	var written := _save()
	if not written:
		return {"ok": false, "code": "S-20", "message": "could not write the memory table"}
	return {"ok": true, "code": "", "message": ""}


func _save() -> bool:
	if backend == null:
		return true
	var text := JSON.stringify(values)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		error = CODE_SHAPE
		return false
	if not backend.write(key(), text):
		error = "S-20"
		return false
	return true


static func _valid_id(id: String) -> bool:
	if id.is_empty():
		return false
	var re := RegEx.new()
	re.compile("^[a-z][a-z0-9_]*$")
	return re.search(id) != null


static func _valid_value(value: Variant) -> bool:
	if value is bool or value is int or value is float or value is String:
		return true
	if value is Array:
		for item in value:
			if not (item is bool or item is int or item is float or item is String):
				return false
		return true
	return false


static func _depth(value: Variant) -> int:
	if value is Array:
		var deepest := 0
		for item in value:
			deepest = maxi(deepest, _depth(item))
		return 1 + deepest
	return 0


static func _same_type(a: Variant, b: Variant) -> bool:
	if a is bool:
		return b is bool
	if a is int or a is float:
		return b is int or b is float
	if a is String:
		return b is String
	if a is Array:
		return b is Array
	return false


static func _coerce(value: Variant) -> Variant:
	## JSON turns every number into a float; a whole number is stored whole, the
	## same rule a save follows (B99), so `score` reads `2`, not `2.0`.
	if value is float and absf(value) < 1.0e15 and value == floor(value):
		return int(value)
	return value


static func _copy(value: Variant) -> Variant:
	if value is Array:
		return (value as Array).duplicate(true)
	return value
