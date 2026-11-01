class_name InstallRegistry
extends RefCounted
## In-memory install registry (SDD §4.3).
##
## Persistence lives one layer up: B4 wires this to storage. B1 only has to keep
## the entry alive for the lifetime of the process and replace it on re-import.

var _entries: Dictionary = {}


func has(plugin_id: String) -> bool:
	return _entries.has(plugin_id)


func version_of(plugin_id: String) -> String:
	if not _entries.has(plugin_id):
		return ""
	return String(_entries[plugin_id]["version"])


func versions() -> Dictionary:
	var out: Dictionary = {}
	for plugin_id in _entries:
		out[plugin_id] = _entries[plugin_id]["version"]
	return out


func count() -> int:
	return _entries.size()


func ids() -> Array:
	return _entries.keys()


func entry(plugin_id: String) -> Dictionary:
	return _entries.get(plugin_id, {})


func install(
	manifest: Dictionary,
	package_bytes: PackedByteArray,
	data: Dictionary = {}
) -> Dictionary:
	## `data` is the parsed payload (`nodes`, `mechanics`) kept in memory so a
	## session never has to open the package again. The persisted record (§4.3)
	## is still `{id, version, manifest, packageBytes}`; this is a runtime cache.
	var record := {
		"id": String(manifest["id"]),
		"version": String(manifest["version"]),
		"manifest": manifest,
		"package_bytes": package_bytes,
		"data": data,
	}
	_entries[record["id"]] = record
	return record


func uninstall(plugin_id: String) -> bool:
	return _entries.erase(plugin_id)


func clear() -> void:
	_entries.clear()
