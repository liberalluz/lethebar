extends SceneTree
## Headless assertions for the package loader (batch B1).
##
## Run: godot --path app --headless -s res://tests/run_tests.gd
##
## The cases are grouped by the STD case they belong to. Anything that needs a
## browser (the import control, the 2 s list refresh, starting a plugin) stays in
## the manual browser pass; what is asserted here is the pipeline underneath it.

const ENGINE_VERSION := "4.7.2"
const FIXTURE_DIR := "res://.test-tmp"
## Staged by infra/stage_builtin.py: the project root is app/, so the shipped
## packages under content/builtin/ are copied in as zips before the suite runs.
const BUILTIN_PACKAGE := "res://builtin/sanguo.zip"

var _failures: Array = []
var _checks := 0


func _initialize() -> void:
	print("lethebar — package loader assertions")
	print("engine %s · fixtures in %s" % [ENGINE_VERSION, FIXTURE_DIR])

	_case_pkg_001()
	_case_pkg_002()
	_case_pkg_003()
	_case_pkg_004()
	_case_pkg_005()
	_case_proto_001()
	_case_proto_002()
	_case_builtin_001()
	_case_det_001()
	_case_save_001()
	_case_save_002()
	_case_package_survives()
	_case_off_003()
	_case_no_clock()

	print("")
	if _failures.is_empty():
		print("OK — %d checks" % _checks)
		quit(0)
	else:
		for failure in _failures:
			printerr("FAIL — %s" % failure)
		print("FAILED — %d checks, %d failures" % [_checks, _failures.size()])
		quit(1)


# --- cases -------------------------------------------------------------------

func _case_pkg_001() -> void:
	_section("TC-PKG-001 valid package imports and appears as installed")
	var loader := PackageLoader.new()
	var result := loader.import_bytes(_package("valid"), _context())
	_check("TC-PKG-001: status is installed", result["status"] == "installed", String(result.get("code", "")))
	_check("TC-PKG-001: registry has one entry", loader.registry.count() == 1)
	_check("TC-PKG-001: name and version survive", loader.registry.version_of("test-linear") == "1.0.0")
	_check("TC-PKG-001: package bytes are kept", not loader.registry.entry("test-linear")["package_bytes"].is_empty())

	_section("TC-PKG-001 re-import of the same version replaces the entry")
	var again := loader.import_bytes(_package("valid"), _context())
	_check("TC-PKG-001: second import still installs", again["status"] == "installed")
	_check("TC-PKG-001: registry still has one entry", loader.registry.count() == 1)


func _case_pkg_002() -> void:
	_section("TC-PKG-002 every rejection names its own code")
	var loader := PackageLoader.new()
	loader.import_bytes(_package("valid"), _context())

	var cases := [
		["V-01 no manifest", _package("no-manifest"), "V-01"],
		["V-01 not a zip", "not a zip at all".to_utf8_buffer(), "V-01"],
		["V-02 missing field", _package("missing-name", {}, ["name"]), "V-02"],
		["V-02 wrong type", _package("bad-type", {"saveSchema": "1"}), "V-02"],
		["V-03 bad id", _package("bad-id", {"id": "Bad_Id"}), "V-03"],
		["V-04 spec window", _package("spec-too-new", {"specVersion": "2.5.0"}), "V-04"],
		["V-05 engine range", _package("engine-old", {"engine": ">=3.0.0 <4.0.0"}), "V-05"],
		["V-06 protocol", _package("unknown-protocol", {"protocol": "sandbox@9"}), "V-06"],
		["V-07 entry node", _package("bad-entry", {"entry": "nope"}), "V-07"],
		["V-09 save schema", _package("bad-save-schema", {"saveSchema": 0}), "V-09"],
	]
	for item in cases:
		var result := loader.import_bytes(item[1], _context())
		_check(
			"TC-PKG-002 %s → %s" % [item[0], item[2]],
			result["status"] == "rejected" and result["code"] == item[2],
			"got %s/%s" % [result["status"], result.get("code", "-")],
		)

	_check("TC-PKG-002: rejections added nothing", loader.registry.count() == 1)
	_check("TC-PKG-002: installed plugin still present", loader.registry.has("test-linear"))

	_section("TC-PKG-002 the same id at another version is refused (SDD §4.2 V-03)")
	var conflicting := loader.import_bytes(
		_package("conflict", {"version": "2.0.0"}), _context()
	)
	_check("V-03 version conflict", conflicting["status"] == "rejected" and conflicting["code"] == "V-03")


func _case_pkg_003() -> void:
	_section("TC-PKG-003 a declared but missing asset warns and still installs")
	var loader := PackageLoader.new()
	var result := loader.import_bytes(
		_package("missing-asset", {"assets": [{"type": "texture", "path": "assets/textures/bg.png"}]}),
		_context(),
	)
	_check("TC-PKG-003: installs anyway", result["status"] == "installed", String(result.get("code", "")))
	var codes: Array = []
	for issue in result.get("issues", []):
		codes.append(issue["code"])
	_check("TC-PKG-003: warning carries V-08", codes.has("V-08"), str(codes))
	_check("TC-PKG-003: warning is not fatal", result["warnings"].size() >= 1)

	_section("TC-PKG-003 an unknown asset type is skipped, not rejected")
	var typed := loader.import_bytes(
		_package("unknown-asset-type", {
			"id": "test-unknown-asset",
			"assets": [{"type": "hologram", "path": "assets/textures/bg.png"}],
		}, [], ["assets/textures/bg.png"]),
		_context(),
	)
	_check("TC-PKG-003: unknown type installs", typed["status"] == "installed", String(typed.get("code", "")))


func _case_pkg_004() -> void:
	_section("TC-PKG-004 several plugins coexist, each with its own version")
	var loader := PackageLoader.new()
	loader.import_bytes(_package("valid"), _context())
	loader.import_bytes(
		_package("second", {"id": "test-turn", "name": "Test Turn", "protocol": "linear@1", "entry": "n1"}),
		_context(),
	)
	loader.import_bytes(
		_package("third", {"id": "test-third", "name": "Test Third", "protocol": "linear@1"}),
		_context(),
	)
	_check("TC-PKG-004: three entries", loader.registry.count() == 3, str(loader.registry.versions()))
	var versions := loader.registry.versions()
	_check("TC-PKG-004: distinct ids kept apart", versions.has("test-linear") and versions.has("test-turn") and versions.has("test-third"))


func _case_pkg_005() -> void:
	_section("TC-PKG-005 a package written from the spec alone needs no engine change")
	# The fixture below is built only from SDD §3.2 field names. If the loader
	# needed anything the spec does not mention, this import would fail.
	var loader := PackageLoader.new()
	var spec_only := _package("spec-only", {
		"id": "spec-only-pack",
		"name": "Spec Only",
		"protocol": "linear@1",
		"capabilities": ["text", "audio"],
		"mechanics": ["momentum"],
		"entry": "start",
	}, [], [], {"nodes": [{"id": "start", "text": "Start.", "choices": []}]})
	var result := loader.import_bytes(spec_only, _context())
	_check("TC-PKG-005: imports unchanged", result["status"] == "installed", String(result.get("code", "")))
	_check("TC-PKG-005: manifest stored verbatim", String(loader.registry.entry("spec-only-pack")["manifest"]["name"]) == "Spec Only")


# --- B2: protocol, session, determinism --------------------------------------

func _case_proto_001() -> void:
	_section("TC-PROTO-001 a linear flow runs from start to an outcome")
	var loader := PackageLoader.new()
	var result := loader.import_bytes(_linear_package("flow"), _context())
	_check("TC-PROTO-001: fixture installs", result["status"] == "installed", String(result.get("code", "")))
	var session := Session.create(loader.registry.entry("test-linear"), {"start_counter": 1})
	_check("TC-PROTO-001: a session can be created", session != null)
	if session == null:
		return
	var opening := session.start()
	_check("TC-PROTO-001: starts at the entry node", opening["node"] == "n1", String(opening["node"]))
	_check("TC-PROTO-001: the node text is shown", opening["text"] == "门口", String(opening["text"]))
	_check("TC-PROTO-001: both choices are offered", opening["choices"].size() == 2, str(opening["choices"]))
	_check("TC-PROTO-001: the progress display is derived", opening.has("progress"), str(opening.keys()))

	var refused := session.choose(9)
	_check("TC-PROTO-001: a choice out of range changes nothing", refused["node"] == "n1", String(refused["node"]))
	_check("TC-PROTO-001: the refusal is a warning", session.warnings.size() >= 1, str(session.warnings))

	var outcome := session.choose(0)
	_check("TC-PROTO-001: a choice advances the node", outcome["node"] == "n2", String(outcome["node"]))
	_check("TC-PROTO-001: the outcome text is shown", outcome["text"] == "左路", String(outcome["text"]))
	_check("TC-PROTO-001: a node without choices finishes", outcome["finished"] == true)
	_check("TC-PROTO-001: the choice effect moved the state", float(outcome["state"].get("power", 0.0)) < 0.0, str(outcome["state"]))
	_check("TC-PROTO-001: the mechanic rule fired", outcome["state"].has("exhausted"), str(outcome["state"]))
	_check("TC-PROTO-001: the snapshot holds the outcome", session.snapshot()["node"] == "n2", str(session.snapshot()))

	var closed := session.choose(0)
	_check("TC-PROTO-001: a finished flow stays put", closed["node"] == "n2", String(closed["node"]))


# --- B3: turn_based@1 and the built-in Sanguo package ------------------------

func _case_proto_002() -> void:
	_section("TC-PROTO-002 a turn-based segment runs three decision rounds to an outcome")
	var loader := PackageLoader.new()
	var installed := loader.import_bytes(_turn_package("turns"), _context())
	_check("TC-PROTO-002: turn-based fixture installs", installed["status"] == "installed", String(installed.get("code", "")))
	var session := Session.create(loader.registry.entry("test-turn"), {"start_counter": 1})
	_check("TC-PROTO-002: a turn-based session can be created", session != null)
	if session == null:
		return
	var opening := session.start()
	_check("TC-PROTO-002: round 1 opens", int(opening.get("round", 0)) == 1, str(opening.get("round", "-")))
	_check("TC-PROTO-002: the entry text is shown", opening["text"] == "第一回合", String(opening["text"]))

	var second := session.choose(0)
	_check("TC-PROTO-002: the second round opens", int(second.get("round", 0)) == 2, str(second.get("round", "-")))
	_check("TC-PROTO-002: an intent opens the next round node", second["node"] == "t2", String(second["node"]))
	var third := session.choose(1)
	_check("TC-PROTO-002: the third round opens", int(third.get("round", 0)) == 3, str(third.get("round", "-")))
	_check("TC-PROTO-002: a third round is still playable", not third["finished"], str(third["finished"]))
	var outcome := session.choose(0)
	_check("TC-PROTO-002: the outcome is reached", outcome["finished"] == true, str(outcome["finished"]))
	_check("TC-PROTO-002: the outcome shows its text", outcome["text"] == "结局", String(outcome["text"]))
	_check("TC-PROTO-002: a finished segment reports its last round", int(outcome.get("round", 0)) == 3, str(outcome.get("round", "-")))
	_check("TC-PROTO-002: the round stays out of the save payload", not session.snapshot().has("round"), str(session.snapshot().keys()))

	_section("TC-PROTO-002 declared mechanics are read out; undeclared ones stay absent")
	var rich_loader := PackageLoader.new()
	rich_loader.import_bytes(_readout_package(
		"readout-c", ["power", "progress"],
		{"rules": [{"when": {"key": "power", "op": "gte", "value": 3}, "set": {"regime": "strong"}}]},
		[{"label": "整备", "next": "r2", "effects": [{"power": {"add": 3}}]}],
	), _context())
	var rich := Session.create(rich_loader.registry.entry("test-readout-c"), {"start_counter": 1})
	_check("TC-PROTO-002: readout fixture C creates a session", rich != null)
	if rich != null:
		var rich_open := rich.start()
		_check("TC-PROTO-002: a declared progress mechanic is shown", rich_open.has("progress"), str(rich_open.keys()))
		var rich_after := rich.choose(0)
		_check("TC-PROTO-002: C's own rule table produced the state", String(rich_after["state"].get("regime", "")) == "strong", str(rich_after["state"]))
		_check("TC-PROTO-002: the readout is C's value, not a default", float(rich_after["state"].get("power", -1.0)) == 3.0, str(rich_after["state"]))

	var bare_loader := PackageLoader.new()
	bare_loader.import_bytes(_readout_package(
		"readout-d", [],
		{},
		[{"label": "整备", "next": "r2", "effects": []}],
	), _context())
	var bare := Session.create(bare_loader.registry.entry("test-readout-d"), {"start_counter": 1})
	_check("TC-PROTO-002: readout fixture D creates a session", bare != null)
	if bare != null:
		var bare_open := bare.start()
		_check("TC-PROTO-002: no progress display without the mechanic", not bare_open.has("progress"), str(bare_open.keys()))
		_check("TC-PROTO-002: no default state is invented", bare_open["state"].is_empty(), str(bare_open["state"]))


func _case_builtin_001() -> void:
	_section("TC-BUILTIN-001 Sanguo plays three decision turns from the shipped package")
	var loader := PackageLoader.new()
	var package := FileAccess.get_file_as_bytes(BUILTIN_PACKAGE)
	if package.is_empty():
		_failures.append("staged package missing at %s; run infra/stage_builtin.py" % BUILTIN_PACKAGE)
		return
	var result := loader.import_bytes(package, _context())
	_check(
		"TC-BUILTIN-001: the shipped package installs",
		result["status"] == "installed",
		"%s %s" % [String(result.get("code", "-")), String(result.get("message", ""))],
	)
	_check("TC-BUILTIN-001: it installs with no warnings", result.get("warnings", []).is_empty(), str(result.get("warnings", [])))
	if result["status"] != "installed":
		return
	var session := Session.create(loader.registry.entry("sanguo"), {"start_counter": 1})
	_check("TC-BUILTIN-001: a Sanguo session starts", session != null)
	if session == null:
		return
	var view := session.start()
	_check("TC-BUILTIN-001: the entry scene shows text", String(view["text"]) != "")
	_check("TC-BUILTIN-001: the entry scene offers a next step", view["choices"].size() >= 1)
	var chosen: Array = []
	var turn := 0
	while turn < 3:
		var offered: Array = view["choices"]
		if offered.is_empty():
			break
		chosen.append(String(offered[0]["label"]))
		view = session.choose(0)
		turn += 1
	_check("TC-BUILTIN-001: all three turns are playable", chosen.size() == 3, str(chosen))
	_check("TC-BUILTIN-001: the end node is reached", view["finished"] == true)
	_check("TC-BUILTIN-001: the end node shows its text", String(view["text"]) != "")
	_check("TC-BUILTIN-001: the power supply mechanic ran", view["state"].has("standing"), str(view["state"]))
	# Step 4 of the case (save to slot 1, reload, resume) needs the save store from
	# B4; the gap is recorded in the B3 exit record instead of being asserted here.


func _case_det_001() -> void:
	_section("TC-DET-001 the same choices reproduce the same snapshot")
	var loader := PackageLoader.new()
	loader.import_bytes(_linear_package("determinism"), _context())
	var entry := loader.registry.entry("test-linear")
	var first := _play(entry, 1)
	var again := _play(entry, 1)
	var other := _play(entry, 2)
	_check("TC-DET-001: the same seed repeats exactly", first == again, first)
	_check("TC-DET-001: another seed diverges", first != other, first)
	_check(
		"TC-DET-001: no clock leaks into the payload",
		not first.contains("savedAt") and not first.contains("\"time\""),
		first,
	)
	var keys: Array = JSON.parse_string(first).keys()
	keys.sort()
	var expected := ["finished", "node", "plugin", "protocol", "rng", "schema", "state", "version", "visited"]
	_check("TC-DET-001: the payload keeps its declared shape", str(keys) == str(expected), str(keys))


func _case_save_001() -> void:
	_section("TC-SAVE-001 three slots per plugin, readable after a reload")
	MemoryBackend.reset()
	var entry: Dictionary = PackageLoader.new().import_bytes(_turn_package("saves"), _context())["entry"]
	var store := SaveStore.new()
	var session := Session.create(entry)
	session.start()
	var written := store.write(entry, 1, session.snapshot(), "第一回合")
	_check("TC-SAVE-001: slot 1 accepts a save", written["ok"], String(written["message"]))
	session.choose(0)
	session.choose(0)
	var later := session.snapshot()
	_check("TC-SAVE-001: the run moved forward before the second save", later["node"] == "t3", String(later["node"]))
	_check("TC-SAVE-001: slot 2 accepts a save", store.write(entry, 2, later, "第三回合")["ok"])

	var after := SaveStore.new()
	var first_read := after.read(entry, 1)
	var second_read := after.read(entry, 2)
	var first_again := after.read(entry, 1)
	_check("TC-SAVE-001: slot 1 reads back after the reload", first_read["ok"] and first_read["payload"]["node"] == "t1", str(first_read))
	_check("TC-SAVE-001: slot 2 reads back after the reload", second_read["ok"] and second_read["payload"]["node"] == "t3", str(second_read))
	_check("TC-SAVE-001: slot 1 reads back a second time", first_again["ok"] and first_again["payload"]["node"] == "t1", str(first_again))
	_check("TC-SAVE-001: slot 3 is writable on the same run", after.write(entry, 3, later)["ok"] and after.read(entry, 3)["ok"])

	var rows := after.slots(entry)
	_check("TC-SAVE-001: the slot list always has three rows", rows.size() == 3, str(rows.size()))
	_check("TC-SAVE-001: a filled row carries saved-at and preview", rows[0]["savedAt"] != "" and rows[0]["preview"] == "第一回合", str(rows[0]))
	_check("TC-SAVE-001: every row reports its slot number", rows[0]["slot"] == 1 and rows[2]["slot"] == 3, str(rows))

	var resumed := after.resume(entry, first_read["payload"])
	_check("TC-SAVE-001: resume returns to the saved node", resumed != null and resumed.current == "t1", "null" if resumed == null else resumed.current)

	var other: Dictionary = PackageLoader.new().import_bytes(_linear_package("saves-other"), _context())["entry"]
	var other_store := SaveStore.new()
	var other_read := other_store.read(other, 1)
	_check("TC-SAVE-001: a second plugin starts with empty slots", not other_read["ok"] and String(other_read["code"]) == SaveStore.CODE_EMPTY, str(other_read))
	var other_rows := other_store.slots(other)
	_check("TC-SAVE-001: an untouched slot row is marked empty", other_rows[0]["empty"] == true, str(other_rows[0]))
	_check("TC-SAVE-001: the first plugin's slots are untouched", other_store.read(entry, 1)["ok"])


func _case_save_002() -> void:
	_section("TC-SAVE-002 an unknown save schema is refused, not migrated")
	MemoryBackend.reset()
	var entry: Dictionary = PackageLoader.new().import_bytes(_turn_package("schema-gate"), _context())["entry"]
	var store := SaveStore.new()
	var session := Session.create(entry)
	session.start()
	_check("TC-SAVE-002: a valid save lands in slot 2", store.write(entry, 2, session.snapshot())["ok"])

	var injected := {
		"schema": 2.0,
		"plugin": {"id": "test-turn", "version": "1.0.0"},
		"node": "t1",
		"state": {},
		"rng": 7,
		"visited": ["t1"],
		"finished": false,
		"savedAt": "2026-01-01T00:00:00",
	}
	_check(
		"TC-SAVE-002: an unknown schema is injected into slot 1",
		MemoryBackend.new().write(SaveStore.key_for("test-turn", 1), JSON.stringify(injected)),
	)
	var refused := store.read(entry, 1)
	_check("TC-SAVE-002: loading it is refused", not refused["ok"], str(refused))
	_check("TC-SAVE-002: the refusal names the schema rule", String(refused["code"]) == SaveStore.CODE_SCHEMA, String(refused["code"]))
	_check(
		"TC-SAVE-002: the message names both versions",
		String(refused["message"]).contains("2") and String(refused["message"]).contains("1"),
		String(refused["message"]),
	)
	_check(
		"TC-SAVE-002: the refused payload is not rewritten",
		MemoryBackend.new().read(SaveStore.key_for("test-turn", 1)).contains("\"schema\":2"),
	)
	var good := store.read(entry, 2)
	_check("TC-SAVE-002: the valid slot still loads", good["ok"], str(good))
	var resumed := store.resume(entry, good["payload"])
	_check("TC-SAVE-002: the game stays interactive after a refusal", resumed != null and resumed.choose(0)["node"] == "t2")


func _case_package_survives() -> void:
	_section("TC-OFF-004 an imported package survives a reload with no network")
	MemoryBackend.reset()
	var entry: Dictionary = PackageLoader.new().import_bytes(_linear_package("offline"), _context())["entry"]
	_check("TC-OFF-004: the imported package is persisted", PackageStore.new().persist(entry))

	var reloaded := PackageLoader.new()
	var restored := PackageStore.new().restore_into(reloaded, _context())
	_check("TC-OFF-004: it comes back installed", restored.has("test-linear"), str(restored))
	_check("TC-OFF-004: the registry holds one plugin", reloaded.registry.count() == 1, str(reloaded.registry.count()))
	var session := Session.create(reloaded.registry.entry("test-linear"))
	_check("TC-OFF-004: the restored plugin builds a session", session != null)
	if session == null:
		return
	session.start()
	session.choose(0)
	_check("TC-OFF-004: it is playable from storage alone", session.current == "n2", session.current)


func _case_off_003() -> void:
	_section("TC-OFF-003 the runtime makes zero network requests")
	var banned := ["HTTPClient", "HTTPRequest", "fetch(", "XMLHttpRequest", "NetworkedMultiplayer"]
	var sources: Array = []
	for root in ["res://core", "res://protocols"]:
		var found: Array = []
		_collect_files(root, "", found)
		for relative in found:
			sources.append("%s/%s" % [root, relative])
	_check("TC-OFF-003: runtime sources were found", not sources.is_empty(), str(sources.size()))
	var offenders: Array = []
	for path in sources:
		if not String(path).ends_with(".gd"):
			continue
		var source := FileAccess.get_file_as_string(String(path))
		for needle in banned:
			if source.contains(needle):
				offenders.append("%s: %s" % [path, needle])
	_check("TC-OFF-003: no runtime file opens a network path", offenders.is_empty(), str(offenders))


func _case_no_clock() -> void:
	_section("SDD §5 the play layer reads no clock and no disk")
	var banned := ["Time.", "OS.get_", "FileAccess", "DirAccess"]
	for path in [
		"res://core/session.gd",
		"res://protocols/linear_v1.gd",
		"res://protocols/turn_based_v1.gd",
		"res://core/mechanics.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		var hits: Array = []
		for needle in banned:
			if source.contains(needle):
				hits.append(needle)
		_check("%s avoids %s" % [path.get_file(), ", ".join(banned)], source != "" and hits.is_empty(), str(hits))


# --- helpers -----------------------------------------------------------------

func _context() -> Dictionary:
	return {"engine_version": ENGINE_VERSION, "work_dir": FIXTURE_DIR}

func _section(title: String) -> void:
	print("")
	print("· %s" % title)


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("  ok    %s" % label)
	else:
		var suffix := "" if detail == "" else " (%s)" % detail
		print("  FAIL  %s%s" % [label, suffix])
		_failures.append("%s%s" % [label, suffix])


func _manifest_defaults() -> Dictionary:
	return {
		"id": "test-linear",
		"version": "1.0.0",
		"specVersion": "1.0.0",
		"engine": ">=4.3.0 <5.0.0",
		"name": "Test Linear",
		"protocol": "linear@1",
		"capabilities": ["text"],
		"mechanics": ["basic"],
		"entry": "n1",
		"saveSchema": 1,
		"assets": [],
	}


func _package(
	name: String,
	overrides: Dictionary = {},
	drop: Array = [],
	extra_files: Array = [],
	nodes_override: Dictionary = {},
	mechanics_override: Dictionary = {},
) -> PackedByteArray:
	## Builds a fixture zip in res:// and returns its bytes. `extra_files` are
	## paths that exist in the zip with dummy content.
	var manifest := _manifest_defaults()
	for key in overrides:
		manifest[key] = overrides[key]
	for key in drop:
		manifest.erase(key)

	var nodes := nodes_override if not nodes_override.is_empty() else {
		"nodes": [{"id": "n1", "text": "A node.", "choices": []}],
	}
	var mechanics := mechanics_override if not mechanics_override.is_empty() else {
		"rules": [],
	}

	# Fixtures live under res:// so the suite works without a writable user://
	# directory; the folder is git-ignored.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FIXTURE_DIR))
	var path := "%s/%s.zip" % [FIXTURE_DIR, name]
	var packer := ZIPPacker.new()
	if packer.open(path) != OK:
		_failures.append("could not create fixture %s" % name)
		return PackedByteArray()

	if name != "no-manifest":
		_write_entry(packer, "manifest.json", JSON.stringify(manifest, "\t").to_utf8_buffer())
	_write_entry(packer, "data/nodes.json", JSON.stringify(nodes, "\t").to_utf8_buffer())
	_write_entry(packer, "data/mechanics.json", JSON.stringify(mechanics, "\t").to_utf8_buffer())
	for extra in extra_files:
		_write_entry(packer, extra, "placeholder".to_utf8_buffer())
	packer.close()

	return FileAccess.get_file_as_bytes(path)


func _write_entry(packer: ZIPPacker, entry_path: String, bytes: PackedByteArray) -> void:
	packer.start_file(entry_path)
	packer.write_file(bytes)
	packer.close_file()


func _linear_package(name: String) -> PackedByteArray:
	## Three nodes: one decision, two outcomes. The left branch runs the power
	## supply down to where the plugin's own rule marks it exhausted.
	var nodes := {
		"nodes": [
			{
				"id": "n1",
				"text": "门口",
				"assets": [],
				"choices": [
					{"label": "向左", "next": "n2", "effects": [{"power": {"add": -1}}]},
					{"label": "向右", "next": "n3", "effects": []},
				],
			},
			{"id": "n2", "text": "左路", "assets": [], "choices": []},
			{"id": "n3", "text": "右路", "assets": [], "choices": []},
		],
	}
	var mechanics := {
		"rules": [
			{"when": {"key": "power", "op": "lte", "value": -1}, "set": {"exhausted": {"value": true}}},
		],
	}
	return _package(name, {"mechanics": ["power", "progress"]}, [], [], nodes, mechanics)


func _turn_package(name: String) -> PackedByteArray:
	## Three rounds plus an ending: t1 → t2 → t3 → t4, one node per round.
	var nodes := {
		"nodes": [
			{"id": "t1", "text": "第一回合", "assets": [], "choices": [
				{"label": "进军", "next": "t2", "effects": []},
				{"label": "扎营", "next": "t2", "effects": []},
			]},
			{"id": "t2", "text": "第二回合", "assets": [], "choices": [
				{"label": "进军", "next": "t3", "effects": []},
				{"label": "扎营", "next": "t3", "effects": []},
			]},
			{"id": "t3", "text": "第三回合", "assets": [], "choices": [
				{"label": "决战", "next": "t4", "effects": []},
				{"label": "退兵", "next": "t4", "effects": []},
			]},
			{"id": "t4", "text": "结局", "assets": [], "choices": []},
		],
	}
	return _package(name, {
		"id": "test-turn",
		"name": "Test Turn",
		"protocol": "turn_based@1",
		"mechanics": [],
		"entry": "t1",
	}, [], [], nodes)


func _readout_package(name: String, mechanics_list: Array, mechanics: Dictionary, choices: Array) -> PackedByteArray:
	## One decision node that can move a state key, then an ending node, so a case
	## can compare what a session shows with and without declared mechanics.
	var nodes := {
		"nodes": [
			{"id": "r1", "text": "读数", "assets": [], "choices": choices},
			{"id": "r2", "text": "结束", "assets": [], "choices": []},
		],
	}
	return _package(name, {
		"id": "test-%s" % name,
		"name": name,
		"mechanics": mechanics_list,
		"entry": "r1",
	}, [], [], nodes, mechanics)


func _collect_files(dir_path: String, prefix: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var relative := name if prefix == "" else "%s/%s" % [prefix, name]
		if dir.current_is_dir():
			_collect_files("%s/%s" % [dir_path, name], relative, out)
		else:
			out.append(relative)
		name = dir.get_next()
	dir.list_dir_end()


func _play(entry: Dictionary, counter: int) -> String:
	var session := Session.create(entry, {"start_counter": counter})
	if session == null:
		return ""
	session.start()
	session.choose(0)
	return JSON.stringify(session.snapshot())
