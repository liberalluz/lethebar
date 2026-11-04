class_name PackageLoader
extends RefCounted
## Reads a plugin package from bytes, validates it, and installs it (SDD §3–§4).
##
## The loader owns V-01 (zip readable, manifest present) and delegates the rest
## to PackageValidator. It never interprets gameplay.
##
## Godot 4.7 can only open a zip by path (ZIPReader has no buffer entry point),
## so the bytes are staged to a scratch file under `work_dir` for the duration
## of one import and removed again before returning. Callers still deal in
## bytes only; the scratch file is an implementation detail of the reader.

const MANIFEST_PATH := "manifest.json"
const NODES_PATH := "data/nodes.json"
const MECHANICS_PATH := "data/mechanics.json"
const STATE_PATH := "data/state.json"
const RULES_PATH := "data/rules.json"
const DEFAULT_WORK_DIR := "user://pkg"

var registry: InstallRegistry

var _import_counter := 0


func _init(registry_instance: InstallRegistry = null) -> void:
	registry = registry_instance if registry_instance != null else InstallRegistry.new()


func import_bytes(bytes: PackedByteArray, context: Dictionary = {}) -> Dictionary:
	if registry == null:
		registry = InstallRegistry.new()

	var scratch := _stage(bytes, String(context.get("work_dir", DEFAULT_WORK_DIR)))
	if scratch == "":
		return _rejected("V-01", "package", "could not stage the package for reading", [])

	var reader := ZIPReader.new()
	if reader.open(scratch) != OK:
		_discard(scratch)
		return _rejected("V-01", "package", "not a readable zip file", [])

	var files := Array(reader.get_files())
	if not files.has(MANIFEST_PATH):
		reader.close()
		_discard(scratch)
		return _rejected("V-01", "package", "package has no %s" % MANIFEST_PATH, [])

	var manifest_variant: Variant = JSON.parse_string(reader.read_file(MANIFEST_PATH).get_string_from_utf8())
	if not manifest_variant is Dictionary:
		reader.close()
		_discard(scratch)
		return _rejected("V-01", "package", "%s is not a JSON object" % MANIFEST_PATH, [])

	var manifest: Dictionary = manifest_variant
	var node_ids: Array = []
	var data := {"nodes": [], "mechanics": {}, "assets": {}, "i18n": {}, "ledger": {}, "rules": []}

	if files.has(NODES_PATH):
		var nodes_variant: Variant = JSON.parse_string(reader.read_file(NODES_PATH).get_string_from_utf8())
		if nodes_variant is Dictionary and nodes_variant.get("nodes", null) is Array:
			for node in nodes_variant["nodes"]:
				if node is Dictionary and node.has("id"):
					node_ids.append(String(node["id"]))
			data["nodes"] = nodes_variant["nodes"]
	if files.has(MECHANICS_PATH):
		var mechanics_variant: Variant = JSON.parse_string(reader.read_file(MECHANICS_PATH).get_string_from_utf8())
		if mechanics_variant is Dictionary:
			data["mechanics"] = mechanics_variant
	# The ledger and its settlement rules (engine-bricks §1, §2). A package that
	# carries neither keeps the pre-brick behaviour: rules over whatever keys a
	# story happens to write, no bounds.
	if files.has(STATE_PATH):
		var state_variant: Variant = JSON.parse_string(reader.read_file(STATE_PATH).get_string_from_utf8())
		if state_variant is Dictionary:
			data["ledger"] = state_variant
	if files.has(RULES_PATH):
		var rules_variant: Variant = JSON.parse_string(reader.read_file(RULES_PATH).get_string_from_utf8())
		if rules_variant is Dictionary and rules_variant.get("rules", null) is Array:
			data["rules"] = rules_variant["rules"]
	elif data["mechanics"].get("rules", null) is Array:
		data["rules"] = data["mechanics"]["rules"]
	# Only the bytes a declared asset actually points at are read, and they stay
	# undecoded: the render layer turns them into a texture or a stream when a
	# scene asks for one (SDD §8.1 — read from memory, never from disk mid-run).
	for asset_path in _referenced_assets(manifest, data["nodes"]):
		if files.has(asset_path):
			data["assets"][asset_path] = reader.read_file(asset_path)
	# A declared locale is carried as one table of text per language. A table
	# that is absent stays absent here; V-22 refuses the package by name, so the
	# player never meets a scene that switches language halfway.
	for locale in _declared_locales(manifest):
		var locale_path := "data/i18n/%s.json" % locale
		if not files.has(locale_path):
			continue
		var table_variant: Variant = JSON.parse_string(reader.read_file(locale_path).get_string_from_utf8())
		if table_variant is Dictionary:
			data["i18n"][locale] = table_variant
	reader.close()
	_discard(scratch)

	var check_context := context.duplicate()
	check_context.erase("work_dir")
	check_context["package_files"] = files
	check_context["node_ids"] = node_ids
	check_context["nodes"] = data["nodes"]
	check_context["i18n"] = data["i18n"]
	check_context["ledger"] = data["ledger"]
	check_context["rules"] = data["rules"]
	check_context["installed"] = registry.versions()
	if not check_context.has("protocols"):
		check_context["protocols"] = ProtocolRegistry.known_ids()

	var issues := PackageValidator.validate(manifest, check_context)
	var fatal := PackageValidator.first_fatal(issues)
	if not fatal.is_empty():
		return _rejected(String(fatal["code"]), String(fatal["field"]), String(fatal["message"]), issues)

	var record := registry.install(manifest, bytes, data)
	var warnings: Array = []
	for issue in issues:
		if not issue.get("fatal", false):
			warnings.append(issue)

	return {
		"status": "installed",
		"entry": record,
		"manifest": manifest,
		"warnings": warnings,
		"issues": issues,
	}


func _referenced_assets(manifest: Dictionary, nodes: Array) -> Array:
	## Every asset path the package points at, declared on the manifest or on a
	## node. Paths are read as written; a path that is not in the zip is left to
	## V-08, which degrades the slot to a placeholder instead of failing.
	var paths: Array = []
	var declared: Variant = manifest.get("assets", [])
	if declared is Array:
		for asset in declared:
			if asset is Dictionary:
				var path := String(asset.get("path", ""))
				if path != "" and not paths.has(path):
					paths.append(path)
	for node in nodes:
		if not node is Dictionary:
			continue
		var node_assets: Variant = node.get("assets", [])
		if not node_assets is Array:
			continue
		for asset in node_assets:
			if asset is Dictionary:
				var path := String(asset.get("path", ""))
				if path != "" and not paths.has(path):
					paths.append(path)
	return paths


func _declared_locales(manifest: Dictionary) -> Array:
	## The extra languages the package claims, in declaration order. The default
	## locale is not listed here: its text is the text in `data/nodes.json`.
	var locales: Array = []
	var declared: Variant = manifest.get("locales", [])
	if declared is Array:
		for raw in declared:
			if raw is String and not locales.has(String(raw)):
				locales.append(String(raw))
	return locales


func _rejected(code: String, field: String, message: String, issues: Array) -> Dictionary:	return {
		"status": "rejected",
		"code": code,
		"field": field,
		"message": message,
		"issues": issues,
	}


# --- scratch file ------------------------------------------------------------

func _stage(bytes: PackedByteArray, work_dir: String) -> String:
	## Writes the package to a scratch file and returns its path, or "" on failure.
	if bytes.is_empty():
		return ""
	var absolute_dir := ProjectSettings.globalize_path(work_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	_import_counter += 1
	var path := "%s/import-%d.zip" % [work_dir, _import_counter]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return path


func _discard(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
