class_name PackageStore
extends RefCounted
## Keeps imported packages as bytes so they are still installed after a reload
## with no network (SDD §9).
##
## It stores the original package bytes, not a parsed mirror: replaying them
## through `PackageLoader.import_bytes` re-runs validation and rebuilds the
## runtime payload, so an offline start sees what the online import saw.

const PREFIX := "package:"

var backend: SaveBackend


func _init(source: SaveBackend = null) -> void:
	backend = source if source != null else MemoryBackend.new()


static func key_for(plugin_id: String) -> String:
	return PREFIX + plugin_id


func persist(entry: Dictionary) -> bool:
	## Call after a successful install; returns whether the bytes really landed.
	var plugin_id := String(entry.get("id", ""))
	var bytes: PackedByteArray = entry.get("package_bytes", PackedByteArray())
	if plugin_id == "" or bytes.is_empty():
		return false
	var blob := {
		"id": plugin_id,
		"version": String(entry.get("version", "")),
		"bytes": Marshalls.raw_to_base64(bytes),
	}
	return backend.write(key_for(plugin_id), JSON.stringify(blob))


func ids() -> Array:
	var out: Array = []
	for key in backend.keys():
		if String(key).begins_with(PREFIX):
			out.append(String(key).substr(PREFIX.length()))
	out.sort()
	return out


func restore_into(loader: PackageLoader, context: Dictionary = {}) -> Array:
	## Re-imports every stored package into `loader`; returns the ids that made it
	## back, so a caller can report the ones that did not.
	var restored: Array = []
	for plugin_id in ids():
		var parsed: Variant = JSON.parse_string(backend.read(key_for(plugin_id)))
		if not parsed is Dictionary:
			continue
		var bytes := Marshalls.base64_to_raw(String(parsed.get("bytes", "")))
		if bytes.is_empty():
			continue
		var result := loader.import_bytes(bytes, context)
		if String(result.get("status", "")) == "installed":
			restored.append(String(result["entry"]["id"]))
	return restored


func erase(plugin_id: String) -> bool:
	return backend.erase(key_for(plugin_id))
