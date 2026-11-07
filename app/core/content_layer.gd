class_name ContentLayer
extends RefCounted

## How a story reads, declared by the package instead of guessed by the engine
## (REQ-044). A package may declare `view` (who the story is told from),
## `density` (how much the readout shows), `cast` (who is in it) and `arc` (what
## the run is called at a given turn). A package that declares none of them keeps
## the shape it had before this class existed, which is why every reader here is
## tolerant of an empty block.

const VIEWS: Array = ["first", "third", "ensemble"]
const DENSITIES: Array = ["sparse", "normal", "dense"]
const DEFAULT_VIEW := "first"
const DEFAULT_DENSITY := "normal"


static func declares(block: Variant) -> bool:
	## True only when the package wrote something worth honouring.
	if not (block is Dictionary):
		return false
	var raw := block as Dictionary
	if raw.is_empty():
		return false
	return raw.has("view") or raw.has("density") or raw.has("cast") or raw.has("arc")


static func defines(block: Variant) -> Dictionary:
	## Normalises whatever the package wrote into the four keys the engine reads.
	var spec := {"view": DEFAULT_VIEW, "density": DEFAULT_DENSITY, "cast": [], "arc": []}
	if not (block is Dictionary):
		return spec
	var raw := block as Dictionary

	var declared_view: Variant = raw.get("view", DEFAULT_VIEW)
	if declared_view is String and VIEWS.has(String(declared_view)):
		spec["view"] = String(declared_view)

	var declared_density: Variant = raw.get("density", DEFAULT_DENSITY)
	if declared_density is String and DENSITIES.has(String(declared_density)):
		spec["density"] = String(declared_density)

	var cast: Array = []
	var declared_cast: Variant = raw.get("cast", [])
	if declared_cast is Array:
		for entry in declared_cast:
			if entry is Dictionary:
				var member := entry as Dictionary
				cast.append({
					"id": String(member.get("id", "")),
					"name": String(member.get("name", "")),
					"role": String(member.get("role", "")),
				})
	spec["cast"] = cast

	var arc: Array = []
	var declared_arc: Variant = raw.get("arc", [])
	if declared_arc is Array:
		for entry in declared_arc:
			if entry is Dictionary:
				var stage := entry as Dictionary
				arc.append({
					"turn": int(stage.get("turn", 0)),
					"label": String(stage.get("label", "")),
				})
	spec["arc"] = arc
	return spec


static func view_of(spec: Dictionary) -> String:
	return String(spec.get("view", DEFAULT_VIEW))


static func density_of(spec: Dictionary) -> String:
	return String(spec.get("density", DEFAULT_DENSITY))


static func cast_of(spec: Dictionary) -> Array:
	return (spec.get("cast", []) as Array).duplicate(true)


static func cast_line(spec: Dictionary, with_roles: bool) -> String:
	## One line naming who is in the story. `ensemble` asks for the roles too,
	## because that view is the one where the reader has to keep track of them.
	var cast := spec.get("cast", []) as Array
	if cast.is_empty():
		return ""
	var parts: Array = []
	for entry in cast:
		var member := entry as Dictionary
		var name := String(member.get("name", ""))
		if name == "":
			continue
		var role := String(member.get("role", ""))
		if with_roles and role != "":
			parts.append("%s (%s)" % [name, role])
		else:
			parts.append(name)
	return ", ".join(parts)


static func arc_at(spec: Dictionary, turn: int) -> Dictionary:
	## The stage whose turn is the last one not after the current turn, or an
	## empty dictionary before the first stage.
	var arc := spec.get("arc", []) as Array
	var chosen := {}
	for entry in arc:
		var stage := entry as Dictionary
		if int(stage.get("turn", 0)) <= turn:
			chosen = stage
	return chosen


static func views() -> Array:
	return VIEWS.duplicate()


static func densities() -> Array:
	return DENSITIES.duplicate()
