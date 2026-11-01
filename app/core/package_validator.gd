class_name PackageValidator
extends RefCounted
## Validation checks V-02..V-09 from SDD §4.2. V-01 belongs to the loader,
## because it needs the zip bytes rather than the manifest.

const KNOWN_PROTOCOLS := ["linear@1", "turn_based@1"]

## Supported specVersion window for v0.0.0 (SRS `TBD-003`).
const SPEC_MIN := "1.0.0"
const SPEC_MAX := "2.0.0"

const SUPPORTED_ASSET_TYPES := ManifestSchema.ASSET_TYPES


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
	var protocols: Array = context.get("protocols", KNOWN_PROTOCOLS)
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

	return issues
