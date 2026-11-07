class_name PackageValidator
extends RefCounted
## Validation checks V-02..V-09 from SDD §4.2. V-01 belongs to the loader,
## because it needs the zip bytes rather than the manifest.

## Protocols that can actually play a package right now. `V-06` reads this list
## instead of a hard-coded copy, so "declared but not implemented" cannot drift
## from the registry (SDD §5.2). `turn_based@1` joins the registry with B3.
static func known_protocols() -> Array:
	return ProtocolRegistry.known_ids()

## Supported specVersion window. `1.0.0` is still readable (ADR-0007) and `2.0.0`
## is current, so the window has to include both; the upper bound is the version
## after next, not the current one.
const SPEC_MIN := "1.0.0"
const SPEC_MAX := "3.0.0"

const SUPPORTED_ASSET_TYPES := ManifestSchema.ASSET_TYPES

## Locales the engine can pick between right now. A package may only declare
## these; anything else is refused rather than silently played in the wrong
## language (V-22).
const SUPPORTED_LOCALES := ["en", "zh-CN"]

## Capabilities this engine can provide (ADR-0008). Each id has a row in
## `docs/specs/capabilities.md`, and a package that asks for anything else is
## refused by name (V-27). The first three are what the renderer draws; the rest
## are the bricks as they exist in this build.
const KNOWN_CAPABILITIES := [
	"text@1",
	"render.2d@1",
	"audio@1",
	"narrative@1",
	"rounds@1",
	"ledger@1",
	"rules@1",
	"menu@1",
	"phases@1",
	"pools@1",
	"relations@1",
	"conditions@1",
	"draws@1",
	"clock@1",
	"actions@1",
	"cards.hand@1",
	"assets@1",
	"locale@1",
	"save@2",
	"offline@1",
	"format@2",
]


static func known_capabilities() -> Array:
	## The test reads this instead of a second copy, so the specification and the
	## engine cannot drift without one of them failing.
	return KNOWN_CAPABILITIES


static func _issue(code: String, field: String, message: String, fatal: bool) -> Dictionary:	return {"code": code, "field": field, "message": message, "fatal": fatal}


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

	# V-32 / W-04 — the world a package belongs to is well formed, and two packs
	# that describe the same world agree on how it is written (ADR-0012).
	var collection := ManifestSchema.collection_of(manifest)
	if not collection.is_empty():
		var world_id := String(collection.get("id", ""))
		var names: Variant = collection.get("names", {})
		if not ManifestSchema.is_collection_id(world_id):
			issues.append(_issue("V-32", "collection", "id must match [a-z0-9-]+", true))
		elif not (names is Dictionary) or (names as Dictionary).is_empty():
			issues.append(_issue("V-32", "collection", "names must map a locale to a title", true))
		else:
			var broken := false
			for locale in (names as Dictionary):
				var title: Variant = (names as Dictionary)[locale]
				if not (title is String) or (title as String).strip_edges() == "":
					broken = true
					break
			if broken:
				issues.append(_issue("V-32", "collection", "names must map a locale to a title", true))
			else:
				# A world already installed under another spelling is one world; the
				# title comes from the pack whose id sorts first, so it is stable.
				var seen: Dictionary = context.get("collections", {})
				for other_id in seen:
					var other: Variant = seen[other_id]
					if not (other is Dictionary) or String((other as Dictionary).get("id", "")) != world_id:
						continue
					var other_names: Variant = (other as Dictionary).get("names", {})
					if JSON.stringify(other_names) != JSON.stringify(names):
						issues.append(_issue(
							"W-04", "collection",
							"the world %s is already described by %s; the engine keeps that title" % [world_id, other_id],
							false,
						))
					break

	# V-04 — authored against a spec version the engine still understands.
	if not ManifestSchema.version_in_range(manifest["specVersion"], SPEC_MIN, SPEC_MAX):
		issues.append(_issue(
			"V-04", "specVersion",
			"outside the supported window %s .. <%s" % [SPEC_MIN, SPEC_MAX],
			true,
		))
	elif ManifestSchema.semver_cmp(
		ManifestSchema.parse_semver(manifest["specVersion"]),
		ManifestSchema.parse_semver(ManifestSchema.SPEC_V2),
	) < 0:
		# W-01 — a package written for format 1.0.0 still installs; the warning
		# names what is missing before the window closes in v0.2.0 (ADR-0007).
		issues.append(_issue(
			"W-01", "specVersion",
			"package declares %s; format %s is current and %s is refused from v0.2.0" % [
				manifest["specVersion"], ManifestSchema.SPEC_V2, manifest["specVersion"],
			],
			false,
		))

	# V-23 — the format 2.0.0 fields have the right shape. Checked after V-02 so a
	# manifest whose basic fields are malformed is reported once, not twice.
	for item in ManifestSchema.format_issues(manifest):
		issues.append(_issue("V-23", item["field"], item["message"], true))

	# V-27 — every capability the package asks for is one this engine provides
	# (ADR-0008). The field has always said what a package needs from the engine;
	# until this check existed nothing read it. A package written for format 1.0.0
	# may still carry the unversioned form that format used, and installs with
	# W-03 so that published packages do not stop working (ADR-0006).
	var legacy_format := ManifestSchema.semver_cmp(
		ManifestSchema.parse_semver(manifest["specVersion"]),
		ManifestSchema.parse_semver(ManifestSchema.SPEC_V2),
	) < 0
	for entry in manifest["capabilities"]:
		var parsed_capability := ManifestSchema.parse_capability(entry)
		if parsed_capability.is_empty():
			if legacy_format:
				issues.append(_issue(
					"W-03", "capabilities",
					"%s names no version; format %s requires %s@<major>" % [
						entry, ManifestSchema.SPEC_V2, entry,
					],
					false,
				))
				continue
			issues.append(_issue(
				"V-27", "capabilities",
				"not a capability id: %s (expected name@major, for example text@1)" % entry,
				true,
			))
			continue
		var capability := ManifestSchema.capability_id(parsed_capability[0], parsed_capability[1])
		if not KNOWN_CAPABILITIES.has(capability):
			issues.append(_issue(
				"V-27", "capabilities",
				"this engine does not provide %s" % capability,
				true,
			))

	# V-24 — every requirement is satisfiable right now. A bundle that needs a
	# package nobody installed is refused at install time, because the player
	# would otherwise reach the scene where it runs out (ADR-0007).
	var catalog: Dictionary = context.get("catalog", context.get("installed", {}))
	for requirement in manifest.get("requires", []):
		if not requirement is Dictionary:
			continue
		var required_id := String(requirement.get("id", ""))
		var constraint: Array = ManifestSchema.parse_engine_range(requirement.get("version", ""))
		if constraint.is_empty():
			continue
		var available := String(catalog.get(required_id, ""))
		if available == "":
			issues.append(_issue(
				"V-24", "requires",
				"requires %s %s, which is neither installed nor built in" % [required_id, requirement["version"]],
				true,
			))
		elif not ManifestSchema.version_in_range(available, constraint[0], constraint[1]):
			issues.append(_issue(
				"V-24", "requires",
				"requires %s %s, but %s is installed" % [required_id, requirement["version"], available],
				true,
			))

	# V-40, V-41 — the content layer a package declares (REQ-044).
	# The engine can only honour a view and a density it knows, and a cast or
	# an arc that contradicts itself would read differently on every load, so
	# both are refused where the package is installed rather than at play time.
	var content_raw: Variant = context.get("content", {})
	if ContentLayer.declares(content_raw):
		var content_spec := ContentLayer.defines(content_raw)
		var declared := content_raw as Dictionary
		if declared.has("view") and String(declared.get("view", "")) != "":
			if not ContentLayer.VIEWS.has(String(declared.get("view", ""))):
				issues.append(_issue(
					"V-40", "manifest.json",
					"content view %s is not one of %s" % [
						String(declared.get("view", "")), ", ".join(ContentLayer.VIEWS),
					],
					true,
				))
		if declared.has("density") and String(declared.get("density", "")) != "":
			if not ContentLayer.DENSITIES.has(String(declared.get("density", ""))):
				issues.append(_issue(
					"V-40", "manifest.json",
					"content density %s is not one of %s" % [
						String(declared.get("density", "")), ", ".join(ContentLayer.DENSITIES),
					],
					true,
				))
		var cast_seen := {}
		for member in content_spec.get("cast", []) as Array:
			var cast_entry := member as Dictionary
			var cast_id := String(cast_entry.get("id", ""))
			var cast_name := String(cast_entry.get("name", ""))
			if cast_id == "" or cast_name == "":
				issues.append(_issue(
					"V-41", "manifest.json",
					"a cast member needs a name and an id: %s" % JSON.stringify(cast_entry),
					true,
				))
				continue
			if cast_seen.has(cast_id):
				issues.append(_issue(
					"V-41", "manifest.json",
					"the cast names %s twice" % cast_id,
					true,
				))
				continue
			cast_seen[cast_id] = true
		var previous := 0
		for stage_entry in content_spec.get("arc", []) as Array:
			var stage := stage_entry as Dictionary
			var stage_turn := int(stage.get("turn", 0))
			var stage_label := String(stage.get("label", ""))
			if stage_turn <= previous or stage_label == "":
				issues.append(_issue(
					"V-41", "manifest.json",
					"the arc must name a label at ascending turns; %d follows %d" % [
						stage_turn, previous,
					],
					true,
				))
				continue
			previous = stage_turn

	# V-16, V-17, V-18 — the other three bricks, each refused where an author's
	# typo would otherwise become a runtime surprise (engine-bricks, validation
	# surface). They are only checked when the package declares them: a package
	# without a menu, a phase machine or a check is a reading experience.
	var actions: Array = context.get("actions", [])
	var declared_resources: Dictionary = {}
	var actions_ledger: Variant = context.get("ledger", {})
	if actions_ledger is Dictionary and not actions_ledger.is_empty():
		declared_resources = Ledger.definitions(actions_ledger)
	if not actions.is_empty():
		for problem in Menu.problems(actions):
			issues.append(_issue("V-16", "actions.json", String(problem), true))
		for key in Menu.referenced_keys(actions):
			if not declared_resources.is_empty() and not declared_resources.has(key):
				issues.append(_issue("V-16", "actions.json", "action names resource %s, which data/state.json never declares" % key, true))
	var phases: Variant = context.get("phases", {})
	if phases is Dictionary and Phases.declares(phases):
		for problem in Phases.problems(phases):
			issues.append(_issue("V-17", "phases.json", String(problem), true))
	var checks: Array = context.get("checks", [])
	if not checks.is_empty():
		for problem in Checks.problems(checks):
			issues.append(_issue("V-18", "checks.json", String(problem), true))

	# V-19, V-20 — pools and relations. A pool that can be drawn past its end
	# would fail at the table, not at load, so it is refused here; a faction map
	# that points at an id it never declares cannot be resolved at all. An
	# asymmetric pair is only a warning: the engine never rewrites what a package
	# meant (engine-bricks §7).
	var pools: Variant = context.get("pools", [])
	if pools is Array and not (pools as Array).is_empty():
		for problem in Pools.problems(pools):
			issues.append(_issue("V-19", "pools.json", String(problem), true))
	var factions: Variant = context.get("factions", {})
	if factions is Dictionary and not (factions as Dictionary).is_empty():
		for problem in Relations.problems(factions):
			var item: Dictionary = problem
			var code := "V-20" if bool(item.get("fatal", true)) else "W-02"
			issues.append(_issue(code, "factions.json", String(item.get("message", "")), bool(item.get("fatal", true))))

	# V-25, V-26 — a condition that names a relation state or a drawn item, and a
	# draw that names a pool. Both are install-time questions: at the table a typo
	# would look like a door that never opens (REQ-027).
	if not actions.is_empty():
		var thresholds: Dictionary = {}
		var entity_ids: Array = []
		if factions is Dictionary:
			var declared: Variant = factions.get("thresholds", {})
			if declared is Dictionary:
				thresholds = declared
			for entity in factions.get("entities", []):
				if entity is Dictionary:
					entity_ids.append(String(entity.get("id", "")))
		var pool_ids: Array = []
		var pool_items: Array = []
		if pools is Array:
			for pool in pools:
				if not pool is Dictionary:
					continue
				pool_ids.append(String(pool.get("id", "")))
				for item in pool.get("items", []):
					pool_items.append(String(item))
		for action in actions:
			var requires: Variant = action.get("requires", [])
			if requires is Array:
				for condition in requires:
					if not condition is Dictionary:
						continue
					if condition.has("relation"):
						var state_name := String(condition.get("state", ""))
						if not thresholds.has(state_name):
							issues.append(_issue(
								"V-25", "actions.json",
								"relation state %s is never declared in data/factions.json" % state_name,
								true,
							))
						var named: Variant = condition.get("relation")
						if named is Dictionary:
							for side in ["from", "to"]:
								var entity_id := String(named.get(side, ""))
								if entity_id != "" and not entity_ids.has(entity_id):
									issues.append(_issue(
										"V-25", "actions.json",
										"relation names entity %s, which data/factions.json never declares" % entity_id,
										true,
									))
					if condition.has("drawn"):
						var item := String(condition.get("drawn", ""))
						if not pool_items.has(item):
							issues.append(_issue(
								"V-25", "actions.json",
								"drawn condition names %s, which no pool contains" % item,
								true,
							))
			var draws: Variant = action.get("draw", null)
			if draws is Dictionary:
				var pool_id := String(draws.get("pool", ""))
				if not pool_ids.has(pool_id):
					issues.append(_issue(
						"V-26", "actions.json",
						"action %s draws from %s, which data/pools.json never declares" % [String(action.get("id", "")), pool_id],
						true,
					))

	# V-36, V-37, V-38 — a hand, its cards and the deck that names them
	# (REQ-036). A deck is a list of ids and a cost is a set of ledger keys, so
	# both are resolved at install: a typo found when the card is drawn would
	# look like a card that does nothing.
	var hand_raw: Variant = context.get("hand", {})
	var hand_spec: Dictionary = Hand.defines(hand_raw) if hand_raw is Dictionary else {}
	var claims_hand := false
	if manifest.get("capabilities", null) is Array:
		claims_hand = (manifest["capabilities"] as Array).has(Hand.CAPABILITY)
	var has_hand_params := hand_raw is Dictionary and (hand_raw as Dictionary).get("hand", null) is Dictionary
	if claims_hand and (not has_hand_params or not Hand.declared(hand_spec)):
		issues.append(_issue(
			"V-36", "cards.json",
			"claims %s but data/cards.json declares no hand and no deck" % Hand.CAPABILITY,
			true,
		))
	elif Hand.declared(hand_spec):
		var cards: Dictionary = hand_spec.get("cards", {})
		var listed_deck: Array = hand_spec.get("deck", [])
		for card_id in listed_deck:
			if not cards.has(card_id):
				issues.append(_issue(
					"V-38", "cards.json",
					"deck names card %s, which the package never declares" % card_id,
					true,
				))
		var textures := {}
		var declared_assets: Variant = manifest.get("assets", [])
		if declared_assets is Array:
			for asset in declared_assets:
				if asset is Dictionary and String(asset.get("type", "")) == "texture":
					textures[String(asset.get("path", ""))] = true
		# V-39 — a card naming a picture the manifest never declares (REQ-037).
		# A card that silently loses its face is the same defect as one that
		# never had a face, only slower to notice.
		for card_id in cards:
			var pictured: Dictionary = cards[card_id]
			if not pictured.has("icon"):
				continue
			var icon := String(pictured.get("icon", ""))
			if not textures.has(icon):
				issues.append(_issue(
					"V-39", "cards.json",
					"card %s names an icon no texture in the manifest provides: %s" % [card_id, icon],
					true,
				))
		for card_id in cards:
			var entry: Dictionary = cards[card_id]
			var touches: Array = []
			var costs: Variant = entry.get("cost", {})
			if costs is Dictionary:
				touches.append(costs)
			var effects: Variant = entry.get("effects", [])
			if effects is Array:
				for effect in effects:
					if effect is Dictionary:
						touches.append(effect)
			for block in touches:
				for key in block:
					if declared_resources.is_empty() or declared_resources.has(String(key)):
						continue
					issues.append(_issue(
						"V-37", "cards.json",
						"card %s names resource %s, which data/state.json never declares" % [card_id, String(key)],
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

	# V-14 — the ledger and its rules agree. A resource the file never declared
	# cannot be written by a rule: the alternative is a silent zero the player
	# would read as a real number (engine-bricks §1).
	var ledger: Variant = context.get("ledger", {})
	var declared: Dictionary = {}
	if ledger is Dictionary and not ledger.is_empty():
		for problem in Ledger.problems(ledger):
			issues.append(_issue("V-14", "state.json", String(problem), true))
		declared = Ledger.definitions(ledger)
	# The tick is readable by every rule and writable by none, whether or not the
	# package keeps a ledger: time is the engine's, not the author's.
	var timing_rules: Array = context.get("rules", [])
	for rule in timing_rules:
		if not (rule is Dictionary):
			continue
		if _writes_tick(rule):
			issues.append(_issue(
				"V-14", "rules",
				"a rule cannot write %s: the tick is the engine's clock" % ManifestSchema.TICK_KEY,
				true,
			))
		for key in _rule_keys(rule):
			if String(key) == ManifestSchema.TICK_KEY:
				continue
			if ledger is Dictionary and not ledger.is_empty() and not declared.has(key):
				issues.append(_issue(
					"V-14", "rules",
					"rule names resource %s, which data/state.json never declares" % key,
					true,
				))

	# V-21 — a declared clock has to be read. A package that says its growth is
	# counted in turns but ships no rule looking at the tick has declared a
	# mechanic it never uses, which is the kind of mistake an author cannot see.
	var clock: Variant = manifest.get("clock", null)
	if clock is Dictionary:
		var per := String(clock.get("per", ""))
		if not ManifestSchema.CLOCK_UNITS.has(per):
			issues.append(_issue(
				"V-21", "clock",
				"clock.per must be one of %s, not %s" % [", ".join(ManifestSchema.CLOCK_UNITS), per],
				true,
			))
		var reads := false
		for rule in timing_rules:
			if rule is Dictionary and _reads_tick(rule):
				reads = true
				break
		if not reads:
			issues.append(_issue(
				"V-21", "clock",
				"a clock is declared but no rule reads the tick",
				true,
			))

	# V-31 — a rule that moves a relation has to name a pair the package declared
	# and a change that is a number. A silent zero would read to the player as a
	# real value, which is the same mistake V-14 refuses for resources.
	var faction_map: Variant = context.get("factions", {})
	var entities: Dictionary = {}
	if faction_map is Dictionary:
		var parsed := Relations.defines(faction_map)
		entities = parsed.get("entities", {})
	for rule in timing_rules:
		if not (rule is Dictionary):
			continue
		var changes: Variant = rule.get("relations", null)
		if changes == null:
			continue
		if not (changes is Array):
			issues.append(_issue("V-31", "rules", "a rule's relations must be an array", true))
			continue
		for change in changes:
			if not (change is Dictionary):
				issues.append(_issue("V-31", "rules", "each relation change must be an object", true))
				continue
			var from_id := String(change.get("from", ""))
			var to_id := String(change.get("to", ""))
			if not entities.has(from_id):
				issues.append(_issue(
					"V-31", "rules",
					"a relation change names %s, which data/factions.json never declares" % from_id,
					true,
				))
			if not entities.has(to_id):
				issues.append(_issue(
					"V-31", "rules",
					"a relation change points at %s, which data/factions.json never declares" % to_id,
					true,
				))
			var amount: Variant = null
			if change.has("add"):
				amount = change["add"]
			elif change.has("value"):
				amount = change["value"]
			else:
				issues.append(_issue("V-31", "rules", "a relation change needs add or value", true))
			if amount != null and not (amount is int or amount is float):
				issues.append(_issue(
					"V-31", "rules",
					"a relation change is not a number: %s" % str(amount),
					true,
				))

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
		var gap := locale_gaps(locale, package_nodes, tables.get(locale, null), _label_keys(context))
		if gap != "":
			issues.append(_issue("V-22", "locales", gap, true))

	return issues


static func _label_keys(context: Dictionary) -> Array:
	## The labels a run is made of, in the order the player meets them: each
	## action, each rank, each labelled value of a resource, each reported failure.
	## A locale table that describes the scene and forgets the menu is the same
	## half-translation V-22 already refuses (REQ-035).
	var keys: Array = []
	for entry in context.get("actions", []):
		if entry is Dictionary:
			keys.append("action.%s" % String(entry.get("id", "")))
	var phases: Variant = context.get("phases", {})
	if phases is Dictionary:
		for entry in phases.get("ranks", []):
			if entry is Dictionary:
				keys.append("rank.%d" % int(entry.get("at", 0)))
		var index := 0
		for entry in phases.get("fail", []):
			if entry is Dictionary:
				keys.append("failure.%d" % index)
			index += 1
	var ledger: Variant = context.get("ledger", {})
	if ledger is Dictionary:
		for id in ledger:
			var entry: Variant = ledger[id]
			if not entry is Dictionary:
				continue
			var labels: Variant = entry.get("labels", null)
			if labels is Dictionary:
				for value in labels:
					keys.append("resource.%s.%s" % [String(id), String(value)])
	return keys


static func locale_gaps(locale: String, nodes: Array, table: Variant, extra_keys: Array = []) -> String:
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
	var strings: Variant = table.get("strings", null)
	if extra_keys.is_empty():
		return ""
	if not strings is Dictionary:
		return "data/i18n/%s.json has no strings section for %s" % [locale, String(extra_keys[0])]
	for key in extra_keys:
		var translated := String(strings.get(String(key), ""))
		if translated.strip_edges() == "":
			return "data/i18n/%s.json has no string for %s" % [locale, String(key)]
	return ""


static func _rule_keys(rule: Dictionary) -> Array:
	## Every resource a rule reads or writes: `when` (one condition or a list of
	## them) and the keys of `set`.
	var keys: Array = []
	var conditions: Variant = rule.get("when", null)
	if conditions is Dictionary:
		keys.append(String(conditions.get("key", "")))
	elif conditions is Array:
		for condition in conditions:
			if condition is Dictionary:
				keys.append(String(condition.get("key", "")))
	var writes: Variant = rule.get("set", null)
	if writes is Dictionary:
		for key in writes:
			keys.append(String(key))
	return keys.filter(func(key): return not String(key).is_empty())


static func _reads_tick(rule: Dictionary) -> bool:
	## A rule reads the tick when its condition names it. Writing it is a
	## different question, and a refused one: the tick is the engine's clock.
	var conditions: Variant = rule.get("when", null)
	if conditions is Dictionary:
		return String(conditions.get("key", "")) == ManifestSchema.TICK_KEY
	if conditions is Array:
		for condition in conditions:
			if condition is Dictionary and String(condition.get("key", "")) == ManifestSchema.TICK_KEY:
				return true
	return false


static func _writes_tick(rule: Dictionary) -> bool:
	var writes: Variant = rule.get("set", null)
	return writes is Dictionary and writes.has(ManifestSchema.TICK_KEY)
