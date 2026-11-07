class_name MetaLayer
extends RefCounted
## What a package says about itself before a reader opens it (REQ-045): a pitch in
## the reader's language, an audience, a length and an icon. The list reads this
## block; a run never does, so declaring it cannot change a save.

const AUDIENCES := ["kids", "teens", "adults"]
const FIELDS := ["pitch", "audience", "minutes", "icon"]


static func declared(manifest: Dictionary) -> bool:
	var raw: Variant = manifest.get("meta", {})
	return raw is Dictionary and not (raw as Dictionary).is_empty()


static func of(manifest: Dictionary) -> Dictionary:
	## The declaration as the list and the validator both want it: a locale map of
	## pitches, an audience, a length and an optional icon path.
	if not declared(manifest):
		return {}
	var raw: Variant = manifest.get("meta", {})
	var block := raw as Dictionary
	var pitches := {}
	var source: Variant = block.get("pitch", {})
	if source is Dictionary:
		for locale in source:
			pitches[String(locale)] = String(source[locale])
	var minutes := 0
	var length: Variant = block.get("minutes", 0)
	if length is int or length is float:
		minutes = int(length)
	return {
		"pitch": pitches,
		"audience": String(block.get("audience", "")),
		"minutes": minutes,
		"icon": String(block.get("icon", "")),
	}


static func pitch(meta: Dictionary, locale: String) -> String:
	## The reader's language first, then the package default the caller passed,
	## then any language the package actually has. A declared block never renders
	## as an empty row.
	var pitches: Dictionary = meta.get("pitch", {})
	if pitches.has(locale) and String(pitches[locale]) != "":
		return String(pitches[locale])
	if pitches.has("en") and String(pitches["en"]) != "":
		return String(pitches["en"])
	for key in pitches:
		if String(pitches[key]) != "":
			return String(pitches[key])
	return ""


static func length_line(meta: Dictionary) -> String:
	var minutes := int(meta.get("minutes", 0))
	if minutes <= 0:
		return ""
	return "%d" % minutes
