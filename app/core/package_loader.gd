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
const ACTIONS_PATH := "data/actions.json"
const PHASES_PATH := "data/phases.json"
const CHECKS_PATH := "data/checks.json"
const POOLS_PATH := "data/pools.json"
const FACTIONS_PATH := "data/factions.json"
const CARDS_PATH := "data/cards.json"
const DISABLE_PATH := "data/disable.json"
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

	# ADR-0009's install-time envelope (REQ-030). Checked before the manifest is
	# read, because none of it should depend on the package being well formed.
	var envelope := _envelope_problem(bytes, files, reader)
	if not envelope.is_empty():
		reader.close()
		_discard(scratch)
		return _rejected(String(envelope["code"]), "package", String(envelope["message"]), [])

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
	var data := {"nodes": [], "mechanics": {}, "assets": {}, "i18n": {}, "ledger": {}, "rules": [], "actions": [], "phases": {}, "checks": [], "pools": [], "factions": {}, "hand": {}, "content": {}}

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
	for entry in [
		{"path": ACTIONS_PATH, "key": "actions", "field": "actions"},
		{"path": PHASES_PATH, "key": "phases", "field": null},
		{"path": CHECKS_PATH, "key": "checks", "field": "checks"},
	]:
		if not files.has(entry["path"]):
			continue
		var variant: Variant = JSON.parse_string(reader.read_file(entry["path"]).get_string_from_utf8())
		if not variant is Dictionary:
			continue
		if entry["field"] == null:
			data["phases"] = variant
		elif variant.get(entry["field"], null) is Array:
			data[entry["key"]] = variant[entry["field"]]
	# A pool is a list to draw from and a faction map is a table of opinions;
	# neither changes the story graph, so a package that carries neither keeps
	# the pre-brick behaviour (engine-bricks §6, §7).
	if files.has(POOLS_PATH):
		var pools_variant: Variant = JSON.parse_string(reader.read_file(POOLS_PATH).get_string_from_utf8())
		if pools_variant is Dictionary and pools_variant.get("pools", null) is Array:
			data["pools"] = pools_variant["pools"]
	if files.has(FACTIONS_PATH):
		var factions_variant: Variant = JSON.parse_string(reader.read_file(FACTIONS_PATH).get_string_from_utf8())
		if factions_variant is Dictionary:
			data["factions"] = factions_variant
	# A hand is a deck, a set of cards and the size of the hand (REQ-036). It is
	# kept whole so the session can deal from it; the validator resolves every
	# card id and every cost key before a run may start.
	if files.has(CARDS_PATH):
		var cards_variant: Variant = JSON.parse_string(reader.read_file(CARDS_PATH).get_string_from_utf8())
		if cards_variant is Dictionary:
			data["hand"] = cards_variant
	var content_variant: Variant = manifest.get("content", {})
	data["content"] = content_variant if content_variant is Dictionary else {}
	# A layer removes entries by name instead of replacing the list that holds
	# them (ADR-0013), so the names it wants gone travel in their own file.
	if files.has(DISABLE_PATH):
		var disable_variant: Variant = JSON.parse_string(reader.read_file(DISABLE_PATH).get_string_from_utf8())
		if disable_variant is Dictionary:
			data["disable"] = disable_variant
	# Only the bytes a declared asset actually points at are read, and they stay
	# undecoded: the render layer turns them into a texture or a stream when a
	# scene asks for one (SDD §8.1 — read from memory, never from disk mid-run).
	var asset_types := {}
	for asset in manifest.get("assets", []):
		if asset is Dictionary:
			asset_types[String(asset.get("path", ""))] = String(asset.get("type", ""))
	for asset_path in _referenced_assets(manifest, data["nodes"]):
		if not files.has(asset_path):
			continue
		var asset_bytes := reader.read_file(asset_path)
		var asset_problem := ""
		match String(asset_types.get(asset_path, "")):
			"texture":
				asset_problem = PackageLimits.texture_problem(
					asset_path, PackageLimits.texture_size(asset_bytes),
				)
			"audio":
				asset_problem = PackageLimits.audio_problem(
					asset_path, asset_bytes.size(), PackageLimits.wav_seconds(asset_bytes),
				)
		if asset_problem != "":
			reader.close()
			_discard(scratch)
			return _rejected("V-30", "assets", asset_problem, [])
		data["assets"][asset_path] = asset_bytes
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
	check_context["actions"] = data["actions"]
	check_context["phases"] = data["phases"]
	check_context["checks"] = data["checks"]
	check_context["pools"] = data["pools"]
	check_context["factions"] = data["factions"]
	check_context["hand"] = data["hand"]
	check_context["content"] = data["content"]
	check_context["installed"] = registry.versions()
	check_context["collections"] = registry.collections()
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


func import_url(url: String, expected_sha256: String, context: Dictionary, fetch: Callable) -> Dictionary:
	## Installs a package that was downloaded rather than handed over (REQ-046).
	##
	## The hash is the only thing standing between a truncated download and a
	## package that installs and then refuses to open, so the bytes are hashed
	## before they reach `import_bytes` and a mismatch stops the install with
	## V-43, naming the expected and the actual digest.
	##
	## The caller supplies the bytes, never a socket: this file lives under
	## `res://core`, and TC-OFF-003 holds that no runtime source in `core` or
	## `protocols` opens a network path. Whoever offers a download (an install
	## screen, a store) passes the fetcher in.
	if not fetch.is_valid():
		return _rejected("V-01", "package", "no fetcher was given for %s" % url, [])
	var fetched: Variant = fetch.call(url)
	if not fetched is PackedByteArray or (fetched as PackedByteArray).is_empty():
		return _rejected("V-01", "package", "could not download the package from %s" % url, [])
	var bytes: PackedByteArray = fetched
	var actual := digest_of(bytes)
	var expected := expected_sha256.strip_edges().to_lower()
	if actual != expected:
		return _rejected(
			"V-43", "package",
			"the package from %s hashes to %s, not the expected %s" % [url, actual, expected],
			[],
		)
	return import_bytes(bytes, context)


static func digest_of(bytes: PackedByteArray) -> String:
	## The sha256 of a package's bytes, lowercase hex, which is the form a
	## descriptor prints and the form `import_url` compares (REQ-046).
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode().to_lower()


func assemble(ids: Array) -> Dictionary:
	## Resolves the ordered package list a run is built from (ADR-0013). A name
	## nothing installed is refused here rather than half-opened later, and the
	## refusal names the package so an author can act on it (V-33).
	##
	## An entry is either a package id or a record that also names `target`: a
	## layer changes the package it sits on instead of adding another story
	## (REQ-042). The chain is accepted only when every target is in the same
	## assembly and the targets do not close on each other, because a cycle is a
	## mistake to report rather than a loop to break (V-34).
	var requests: Array = []
	for raw in ids:
		if raw is Dictionary:
			var record: Dictionary = raw
			requests.append({"id": String(record.get("id", "")), "target": String(record.get("target", ""))})
		else:
			requests.append({"id": String(raw), "target": ""})
	var entries: Array = []
	var names: Array = []
	for request in requests:
		var plugin_id := String(request["id"])
		if not registry.has(plugin_id):
			return {
				"ok": false,
				"code": "V-33",
				"message": "the assembly names %s, which is not installed" % plugin_id,
				"entries": [],
			}
		if names.has(plugin_id):
			return {
				"ok": false,
				"code": "V-34",
				"message": "the assembly names %s twice" % plugin_id,
				"entries": [],
			}
		names.append(plugin_id)
	if entries.is_empty() and names.is_empty():
		return {"ok": false, "code": "V-33", "message": "the assembly names no package", "entries": []}
	for request in requests:
		var target := String(request["target"])
		if target != "" and not names.has(target):
			return {
				"ok": false,
				"code": "V-34",
				"message": "the layer %s sits on %s, which this assembly does not name" % [String(request["id"]), target],
				"entries": [],
			}
		if target != "" and target == String(request["id"]):
			return {
				"ok": false,
				"code": "V-34",
				"message": "the layer %s sits on itself" % String(request["id"]),
				"entries": [],
			}
	var targets := {}
	for request in requests:
		if String(request["target"]) != "":
			targets[String(request["id"])] = String(request["target"])
	for request in requests:
		var walk := String(request["id"])
		var seen: Array = []
		while targets.has(walk):
			if seen.has(walk):
				return {
					"ok": false,
					"code": "V-34",
					"message": "the layer chain returns to %s" % walk,
					"entries": [],
				}
			seen.append(walk)
			walk = String(targets[walk])
	var written := {}
	for request in requests:
		var entry: Dictionary = registry.entry(String(request["id"])).duplicate(true)
		var manifest: Dictionary = entry.get("manifest", {}) if entry.get("manifest", null) is Dictionary else {}
		var target := String(request["target"])
		if target == "":
			target = String(manifest.get("target", ""))
		if target == "" and String(manifest.get("kind", "")) == "layer":
			return {
				"ok": false,
				"code": "V-34",
				"message": "the layer %s names no target, and the assembly names none for it" % String(request["id"]),
				"entries": [],
			}
		if target != "":
			entry["target"] = target
			var target_entry: Dictionary = registry.entry(target)
			if target_entry.is_empty():
				return {
					"ok": false,
					"code": "V-33",
					"message": "the layer %s sits on %s, which is not installed" % [String(request["id"]), target],
					"entries": [],
				}
			var target_manifest: Dictionary = target_entry.get("manifest", {}) if target_entry.get("manifest", null) is Dictionary else {}
			if String(target_manifest.get("kind", ManifestSchema.KIND_BUNDLE)) != ManifestSchema.KIND_BUNDLE:
				return {
					"ok": false,
					"code": "V-44",
					"message": "the layer %s sits on %s, which is a %s, not a bundle" % [
						String(request["id"]), target, String(target_manifest.get("kind", "")),
					],
					"entries": [],
				}
			var clash := _layer_conflict(entry, written)
			if clash != "":
				return {"ok": false, "code": "V-35", "message": clash, "entries": []}
		entry["state"] = _state_of(manifest)
		entries.append(entry)
	var merged: Dictionary = _merge_layer_assets(entries)
	if not merged.get("ok", false):
		return merged
	return {"ok": true, "code": "", "message": "", "entries": entries}


func _merge_layer_assets(entries: Array) -> Dictionary:
	## B92: every applied layer's asset bytes join the bundle's lookup, in
	## assembly order. A path two applied layers both carry is ambiguous before
	## the run starts, so it is refused; a path the bundle also declares is
	## overridden by the layer, like every other layer dimension.
	var base_index := -1
	for i in entries.size():
		var manifest: Dictionary = entries[i].get("manifest", {}) if entries[i].get("manifest", null) is Dictionary else {}
		if String(manifest.get("kind", ManifestSchema.KIND_BUNDLE)) == ManifestSchema.KIND_BUNDLE:
			base_index = i
			break
	if base_index < 0:
		return {"ok": true}
	var base_assets: Dictionary = entries[base_index]["data"]["assets"]
	var owners := {}
	for i in entries.size():
		if i == base_index or String(entries[i].get("state", "")) != "applied":
			continue
		var layer_assets: Dictionary = entries[i]["data"]["assets"]
		for path in layer_assets:
			if owners.has(path):
				return {
					"ok": false,
					"code": "V-45",
					"message": "the layers %s and %s both carry %s" % [
						owners[path], String(entries[i]["id"]), path,
					],
					"entries": [],
				}
			owners[path] = String(entries[i]["id"])
			base_assets[path] = layer_assets[path]
	return {"ok": true}


func _state_of(manifest: Dictionary) -> String:
	## A layer the engine applies turns its tick into a change; one it does not
	## apply is pending, and the pack page says so instead of offering the tick
	## (B91).
	if String(manifest.get("kind", ManifestSchema.KIND_BUNDLE)) != ManifestSchema.KIND_LAYER:
		return "bundle"
	if ManifestSchema.layer_applied(String(manifest.get("layer", ""))):
		return "applied"
	return "pending"


func _layer_conflict(entry: Dictionary, written: Dictionary) -> String:
	## Two layers that write the same field are an authoring mistake, not an
	## order to choose from: the later one would silently win. The refusal names
	## the field and both packages so the author knows which pair to look at
	## (REQ-043, V-35).
	var layer_id := String(entry.get("id", ""))
	var data: Dictionary = entry.get("data", {}) if entry.get("data", null) is Dictionary else {}
	var fields: Array = []
	var ledger: Variant = data.get("ledger", {})
	if ledger is Dictionary:
		for resource in (ledger as Dictionary).get("resources", []):
			if resource is Dictionary and resource.has("id"):
				fields.append(["resource", String(resource["id"])])
	for action in data.get("actions", []):
		if action is Dictionary and action.has("id"):
			fields.append(["action", String(action["id"])])
	for pool in data.get("pools", []):
		if pool is Dictionary and pool.has("id"):
			fields.append(["pool", String(pool["id"])])
	var hand: Variant = data.get("hand", {})
	if hand is Dictionary:
		for card in (hand as Dictionary).get("cards", []):
			if card is Dictionary and card.has("id"):
				fields.append(["card", String(card["id"])])
	for field in fields:
		var key := "%s:%s" % [String(field[0]), String(field[1])]
		if written.has(key):
			return "the layers %s and %s both write %s %s" % [String(written[key]), layer_id, String(field[0]), String(field[1])]
		written[key] = layer_id
	return ""


func _envelope_problem(bytes: PackedByteArray, files: Array, reader: ZIPReader) -> Dictionary:
	## The envelope in `PackageLimits` applied to a real archive: the zip itself,
	## how many entries it holds, the shape of every path, and the bytes each entry
	## unpacks to. Returns `{}` when the package fits.
	var archive := PackageLimits.archive_problem(bytes.size())
	if archive != "":
		return {"code": "V-28", "message": archive}
	var count := PackageLimits.entries_problem(files.size())
	if count != "":
		return {"code": "V-28", "message": count}
	var total := 0
	for path in files:
		var path_text := String(path)
		var shape := PackageLimits.path_problem(path_text)
		if shape != "":
			return {"code": "V-29", "message": shape}
		var entry := reader.read_file(path_text)
		total += entry.size()
		var oversized := PackageLimits.entry_problem(path_text, entry.size())
		if oversized != "":
			return {"code": "V-28", "message": oversized}
	var unpacked := PackageLimits.total_problem(total)
	if unpacked != "":
		return {"code": "V-28", "message": unpacked}
	return {}


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
