class_name ManifestSchema
extends RefCounted
## Field inventory and shape helpers for a plugin manifest (SDD §3.2).
##
## Nothing here knows about gameplay. The schema only describes what a package
## has to look like before the engine is allowed to read it.

const REQUIRED_FIELDS := [
	"id",
	"version",
	"specVersion",
	"engine",
	"name",
	"protocol",
	"capabilities",
	"mechanics",
	"entry",
	"saveSchema",
	"assets",
]

const LIST_FIELDS := ["capabilities", "mechanics", "assets"]
const STRING_FIELDS := ["id", "version", "specVersion", "engine", "name", "protocol", "entry"]

## Optional fields a package may add. The default locale names the language the
## text in `data/nodes.json` is already written in; `locales` lists the extra
## languages the package carries under `data/i18n/<locale>.json`; `names` gives
## the pack's own title per locale.
const OPTIONAL_STRING_FIELDS := ["defaultLocale"]
const OPTIONAL_LIST_FIELDS := ["locales"]
const OPTIONAL_MAP_FIELDS := ["names"]

const ID_PATTERN := "^[a-z0-9-]+$"
const SEMVER_PATTERN := "^(\\d+)\\.(\\d+)\\.(\\d+)$"
const ENGINE_RANGE_PATTERN := "^>=(\\d+\\.\\d+\\.\\d+) <(\\d+\\.\\d+\\.\\d+)$"

const ASSET_TYPES := ["texture", "audio", "text"]


static func _regex(pattern: String) -> RegEx:
	var re := RegEx.new()
	var err := re.compile(pattern)
	assert(err == OK, "invalid pattern: %s" % pattern)
	return re


static func is_id(value: Variant) -> bool:
	return value is String and _regex(ID_PATTERN).search(value) != null


static func is_integer(value: Variant) -> bool:
	## JSON has no integer type, so `1` arrives as a float; accept it only when it
	## carries no fraction.
	if value is int:
		return true
	if value is float:
		return is_finite(value) and value == floor(value)
	return false


static func parse_semver(value: Variant) -> Array:
	if not value is String:
		return []
	var m := _regex(SEMVER_PATTERN).search(value)
	if m == null:
		return []
	return [m.get_string(1).to_int(), m.get_string(2).to_int(), m.get_string(3).to_int()]


static func semver_cmp(left: Array, right: Array) -> int:
	for i in 3:
		if left[i] < right[i]:
			return -1
		if left[i] > right[i]:
			return 1
	return 0


static func parse_engine_range(value: Variant) -> Array:
	if not value is String:
		return []
	var m := _regex(ENGINE_RANGE_PATTERN).search(value)
	if m == null:
		return []
	return [m.get_string(1), m.get_string(2)]


static func version_in_range(version: Variant, low: Variant, high: Variant) -> bool:
	var v := parse_semver(version)
	var lo := parse_semver(low)
	var hi := parse_semver(high)
	if v.is_empty() or lo.is_empty() or hi.is_empty():
		return false
	return semver_cmp(v, lo) >= 0 and semver_cmp(v, hi) < 0


static func field_shape_issues(manifest: Dictionary) -> Array:
	## Returns one entry per malformed field: {field, message}.
	var issues: Array = []
	for field in REQUIRED_FIELDS:
		if not manifest.has(field):
			issues.append({"field": field, "message": "missing required field"})
			continue
		var value: Variant = manifest[field]
		if field in STRING_FIELDS and not value is String:
			issues.append({"field": field, "message": "expected a string"})
		elif field == "saveSchema" and not is_integer(value):
			issues.append({"field": field, "message": "expected an integer"})
		elif field in LIST_FIELDS and not value is Array:
			issues.append({"field": field, "message": "expected an array"})
	for field in OPTIONAL_STRING_FIELDS:
		if manifest.has(field) and not manifest[field] is String:
			issues.append({"field": field, "message": "expected a string"})
	for field in OPTIONAL_LIST_FIELDS:
		if not manifest.has(field):
			continue
		var listed: Variant = manifest[field]
		if not listed is Array:
			issues.append({"field": field, "message": "expected an array"})
			continue
		for entry in listed:
			if not entry is String:
				issues.append({"field": field, "message": "expected an array of locale codes"})
				break
	for field in OPTIONAL_MAP_FIELDS:
		if manifest.has(field) and not manifest[field] is Dictionary:
			issues.append({"field": field, "message": "expected an object keyed by locale"})
	return issues
