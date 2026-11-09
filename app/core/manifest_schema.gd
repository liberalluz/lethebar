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
const OPTIONAL_MAP_FIELDS := ["names", "clock"]
## The only two meanings `clock.per` has: a turn of the action menu, or a node
## of a linear story. Anything else is out of scope for format 2.0.0.
const CLOCK_UNITS := ["turn", "node"]
## The key a settlement rule reads to see how much time the engine counts. It is
## never a resource: a package cannot declare it, and a rule cannot write it.
const TICK_KEY := "tick"

## Format 2.0.0 fields (ADR-0007). `kind` says whether the package is playable on
## its own; `layer` names which piece of the seven-layer design a non-playable
## package is; `requires` lists the packages it needs before it can be played.
const KIND_BUNDLE := "bundle"
const KIND_LAYER := "layer"
const KINDS := [KIND_BUNDLE, KIND_LAYER]
const LAYERS := ["profession", "genre", "mod", "content", "meta", "assets"]
## The dimensions this build applies when a layer is assembled. The other four
## are still declarations: the pack page marks them pending instead of offering
## a tick that would change nothing (B91, ADR-0013).
const APPLIED_LAYERS := ["content", "mod"]
const SPEC_V2 := "2.0.0"


static func layer_applied(dimension: String) -> bool:
	return LAYERS.has(dimension) and APPLIED_LAYERS.has(dimension)

const ID_PATTERN := "^[a-z0-9-]+$"
const SEMVER_PATTERN := "^(\\d+)\\.(\\d+)\\.(\\d+)$"
const ENGINE_RANGE_PATTERN := "^>=(\\d+\\.\\d+\\.\\d+) <(\\d+\\.\\d+\\.\\d+)$"

## A world id is a slug, and its titles are locale -> text. A package that names
## the world it belongs to lets the landing screen offer worlds first
## (ADR-0012); a package that names none belongs to the fallback world.
const COLLECTION_ID_PATTERN := "^[a-z0-9-]+$"


static func is_collection_id(value: Variant) -> bool:
	## A world id uses the same alphabet as a package id.
	return value is String and is_id(value as String)


static func collection_of(manifest: Dictionary) -> Dictionary:
	## The shape alone: an empty dictionary means the package declares no world,
	## and a malformed one is left for V-32 to name.
	var row: Variant = manifest.get("collection", null)
	if row is Dictionary:
		return row
	return {}

const ASSET_TYPES := ["texture", "audio", "text"]

## A capability id is `name@major` (ADR-0008): a lowercase dotted name and a
## positive major version, e.g. `render.2d@1` or `save@2`. The schema knows only
## the shape; which ids the engine actually provides is a constant in
## `PackageValidator`.
const CAPABILITY_PATTERN := "^([a-z][a-z0-9]*(?:\\.[a-z0-9]+)*)@([1-9]\\d*)$"


static func parse_capability(value: Variant) -> Array:
	## Returns `[name, major]`, or `[]` when the value is not a capability id.
	if not value is String:
		return []
	var m := _regex(CAPABILITY_PATTERN).search(value)
	if m == null:
		return []
	return [m.get_string(1), int(m.get_string(2))]


static func capability_id(name: String, major: int) -> String:
	return "%s@%d" % [name, major]


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


static func format_issues(manifest: Dictionary) -> Array:
	## Format 2.0.0 fields, checked separately from the 1.0.0 shape so that a
	## legacy package is not asked for fields its format never had (V-23).
	## Returns one entry per problem: {field, message}.
	var issues: Array = []
	var is_v2 := parse_semver(manifest.get("specVersion", "")) == parse_semver(SPEC_V2)

	var kind := String(manifest.get("kind", ""))
	if kind == "":
		if is_v2:
			issues.append({"field": "kind", "message": "format 2.0.0 requires kind: %s" % ", ".join(KINDS)})
	else:
		if not KINDS.has(kind):
			issues.append({"field": "kind", "message": "expected one of: %s" % ", ".join(KINDS)})
		elif kind == KIND_LAYER:
			var layer := String(manifest.get("layer", ""))
			if layer == "":
				issues.append({"field": "layer", "message": "a layer package must name its layer: %s" % ", ".join(LAYERS)})
			elif not LAYERS.has(layer):
				issues.append({"field": "layer", "message": "expected one of: %s" % ", ".join(LAYERS)})
			# The target sits beside `layer`, not inside it (REQ-043): `layer`
			# already answers which of the six pieces this package is, and a key
			# that means two things depending on its shape is a trap for authors.
			var target: Variant = manifest.get("target", "")
			if String(target) == "":
				issues.append({"field": "target", "message": "a layer package must name the package it changes"})
			elif not is_id(target):
				issues.append({"field": "target", "message": "target must match %s" % ID_PATTERN})
		elif manifest.has("target"):
			issues.append({"field": "target", "message": "only a layer package may name a target"})

	if manifest.has("requires"):
		var requires: Variant = manifest["requires"]
		if not requires is Array:
			issues.append({"field": "requires", "message": "expected an array of {id, version}"})
		else:
			for entry in requires:
				if not entry is Dictionary:
					issues.append({"field": "requires", "message": "each requirement must be an object with id and version"})
					continue
				var required_id := String(entry.get("id", ""))
				if not is_id(required_id):
					issues.append({"field": "requires", "message": "requirement id must match [a-z0-9-]+"})
				elif parse_engine_range(entry.get("version", "")) == []:
					issues.append({
						"field": "requires",
						"message": "requirement %s needs a range like >=1.0.0 <2.0.0" % required_id,
					})
	return issues
