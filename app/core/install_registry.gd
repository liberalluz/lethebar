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


func collections() -> Dictionary:
	## The worlds the installed packages declare, keyed by package id. V-32 and
	## W-04 look at this instead of at `versions()`, which only keeps numbers.
	var out: Dictionary = {}
	for plugin_id in _entries:
		var manifest: Variant = _entries[plugin_id].get("manifest", {})
		if not (manifest is Dictionary):
			continue
		var row := ManifestSchema.collection_of(manifest as Dictionary)
		if not row.is_empty():
			out[plugin_id] = row
	return out


func count() -> int:
	return _entries.size()


func ids() -> Array:
	return _entries.keys()


func entry(plugin_id: String) -> Dictionary:
	## The record has to describe itself. `kind` is the declaration (ADR-0013):
	## `Session.create` applies a record as a layer only when `kind` says so, and
	## merges everything else as an additive package. `layer` and `target` are
	## copied beside it because the assembly chain reads them from the record, not
	## from the manifest. A save replays its assembly through this function, so a
	## copy that dropped any of them would make a layer come back as a package
	## that only adds — its `disable.json` and its overridden definitions would be
	## lost (REQ-043, B80, B86).
	var record: Dictionary = _entries.get(plugin_id, {})
	var manifest: Variant = record.get("manifest", {})
	if not (manifest is Dictionary):
		return record
	var out := record.duplicate()
	for key in ["kind", "layer", "target"]:
		if (manifest as Dictionary).has(key):
			out[key] = (manifest as Dictionary)[key]
	return out


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
