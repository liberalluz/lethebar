class_name PackageValidator
extends RefCounted
## Validation checks V-02..V-09 from SDD §4.2. V-01 belongs to the loader,
## because it needs the zip bytes rather than the manifest.

## Protocols that can actually play a package right now. `V-06` reads this list
## instead of a hard-coded copy, so "declared but not implemented" cannot drift
## from the registry (SDD §5.2). `turn_based@1` joins the registry with B3.
static func known_protocols() -> Array:
	return ProtocolRegistry.known_ids()

## Supported specVersion window for v0.0.0 (SRS `TBD-003`).
const SPEC_MIN := "1.0.0"
const SPEC_MAX := "2.0.0"

const SUPPORTED_ASSET_TYPES := ManifestSchema.ASSET_TYPES

## Locales the engine can pick between right now. A package may only declare
## these; anything else is refused rather than silently played in the wrong
## language (V-22).
const SUPPORTED_LOCALES := ["en", "zh-CN"]


static func _issue(code: String, field: String, message: String, fatal: bool) -> Dictionary:
	return {"code": code, "field": field, "message": message, "fatal": fatal}


static func first_fatal(issues: Array) -> Dictionary:
	for issue in issues:
		if issue.get("fatal", false):
			return issue
	return {}


static func validate(manifest: Dictionary, context: Dictionary) -> Array:
	## context keys: engine_version, protocols, node_ids, package_files, installed
	var issues: Array = []

	var shape := ManifestSchema.field_shape_issues(manifest)
	if not shape.is_empty():
		for item in shape:
			issues.append(_issue("V-02", item["field"], item["message"], true))
		# A manifest that does not even have the right shape cannot be checked
		# any further; reporting one code per bad field is enough.
		return issues

	# V-03 — identity is well formed and does not shadow another version.
	if not ManifestSchema.is_id(manifest["id"]):
		issues.append(_issue("V-03", "id", "must match [a-z0-9-]+", true))
	var installed: Dictionary = context.get("installed", {})
	var installed_version := String(installed.get(manifest["id"], ""))
	if installed_version != "" and installed_version != String(manifest["version"]):
		issues.append(_issue(
			"V-03", "id",
			"already installed at %s; re-import that version or uninstall first" % installed_version,
			true,
		))

	# V-04 — authored against a spec version the engine still understands.
	if not ManifestSchema.version_in_range(manifest["specVersion"], SPEC_MIN, SPEC_MAX):
		issues.append(_issue(
			"V-04", "specVersion",
			"outside the supported window %s .. <%s" % [SPEC_MIN, SPEC_MAX],
			true,
		))

	# V-05 — the engine version this build is, not the one the author hoped for.
	var engine_version := String(context.get("engine_version", "0.0.0"))
	var engine_range := ManifestSchema.parse_engine_range(manifest["engine"])
	if engine_range.is_empty():
		issues.append(_issue("V-05", "engine", "expected a range like >=4.3.0 <5.0.0", true))
	elif not ManifestSchema.version_in_range(engine_version, engine_range[0], engine_range[1]):
		issues.append(_issue(
			"V-05", "engine",
			"range %s..<%s excludes engine %s" % [engine_range[0], engine_range[1], engine_version],
			true,
		))

	# V-06 — the protocol has to exist in the registry.
	var protocols: Array = context.get("protocols", known_protocols())
	if not protocols.has(manifest["protocol"]):
		issues.append(_issue("V-06", "protocol", "unknown protocol: %s" % manifest["protocol"], true))

	# V-07 — the entry node has to exist in the package data.
	var node_ids: Array = context.get("node_ids", [])
	if not node_ids.has(manifest["entry"]):
		issues.append(_issue("V-07", "entry", "entry node not found in data/nodes.json: %s" % manifest["entry"], true))

	# V-09 — saves produced by this plugin need a payload version.
	var save_schema: Variant = manifest["saveSchema"]
	if not ManifestSchema.is_integer(save_schema) or float(save_schema) <= 0.0:
		issues.append(_issue("V-09", "saveSchema", "must be a positive integer", true))

	# V-08 — asset inventory. Never fatal: the node degrades to a placeholder.
	var package_files: Array = context.get("package_files", [])
	for asset in manifest["assets"]:
		if not asset is Dictionary:
			issues.append(_issue("V-02", "assets", "each asset must be an object with type and path", true))
			continue
		var asset_path := String(asset.get("path", ""))
		var asset_type := String(asset.get("type", ""))
		if asset_path == "" or not package_files.has(asset_path):
			issues.append(_issue("V-08", "assets", "declared asset missing from package: %s" % asset_path, false))
		elif not SUPPORTED_ASSET_TYPES.has(asset_type):
			issues.append(_issue("V-08", "assets", "unknown asset type skipped: %s" % asset_type, false))

	# V-22 — a declared locale is complete or the package is refused. Half a
	# translation is worse than none: the player would meet a language switch in
	# the middle of a scene.
	var package_nodes: Array = context.get("nodes", [])
	var tables: Dictionary = context.get("i18n", {})
	if manifest.has("defaultLocale"):
		var default_locale := String(manifest["defaultLocale"])
		if not SUPPORTED_LOCALES.has(default_locale):
			issues.append(_issue(
				"V-22", "defaultLocale",
				"unsupported locale %s; supported: %s" % [default_locale, ", ".join(SUPPORTED_LOCALES)],
				true,
			))
	var locales: Array = manifest.get("locales", [])
	for raw_locale in locales:
		var locale := String(raw_locale)
		if not SUPPORTED_LOCALES.has(locale):
			issues.append(_issue(
				"V-22", "locales",
				"unsupported locale %s; supported: %s" % [locale, ", ".join(SUPPORTED_LOCALES)],
				true,
			))
			continue
		if manifest.has("defaultLocale") and locale == String(manifest["defaultLocale"]):
			issues.append(_issue(
				"V-22", "locales",
				"%s is the default locale; its text lives in data/nodes.json" % locale,
				true,
			))
			continue
		var locale_path := "data/i18n/%s.json" % locale
		if not package_files.has(locale_path):
			issues.append(_issue(
				"V-22", "locales",
				"declared locale %s has no %s" % [locale, locale_path],
				true,
			))
			continue
		var gap := locale_gaps(locale, package_nodes, tables.get(locale, null))
		if gap != "":
			issues.append(_issue("V-22", "locales", gap, true))

	return issues


static func locale_gaps(locale: String, nodes: Array, table: Variant) -> String:
	## Returns the first place a declared locale falls short, or "" when every
	## node and every choice it offers has a label in that language.
	if not table is Dictionary:
		return "data/i18n/%s.json is not a JSON object" % locale
	for node in nodes:
		if not node is Dictionary:
			continue
		var node_id := String(node.get("id", ""))
		var entry_variant: Variant = table.get(node_id, null)
		if not entry_variant is Dictionary:
			return "data/i18n/%s.json has no entry for node %s" % [locale, node_id]
		var text := String(entry_variant.get("text", ""))
		if text.strip_edges() == "":
			return "data/i18n/%s.json leaves node %s without text" % [locale, node_id]
		var choices: Array = node.get("choices", []) if node.get("choices", null) is Array else []
		var labels: Variant = entry_variant.get("choices", null)
		if not labels is Array:
			return "data/i18n/%s.json gives node %s no choice labels" % [locale, node_id]
		if labels.size() != choices.size():
			return "data/i18n/%s.json gives node %s %d labels for %d choices" % [
				locale, node_id, labels.size(), choices.size(),
			]
		for label in labels:
			if not label is String or String(label).strip_edges() == "":
				return "data/i18n/%s.json has an empty label in node %s" % [locale, node_id]
	return ""
