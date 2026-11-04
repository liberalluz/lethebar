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
const BUILTIN_XIUXIAN := "res://builtin/xiuxian.zip"

var _failures: Array = []
var _checks := 0


func _initialize() -> void:
	print("lethebar — package loader assertions")
	print("engine %s · fixtures in %s" % [ENGINE_VERSION, FIXTURE_DIR])
	# Every assertion below reads the interface through `Locale`, and `Locale`
	# remembers the last choice in `user://`. Pin English first so the suite
	# does not depend on what the previous run left behind; `_case_locale` puts
	# it back before it finishes.
	Locale.set_current("en")

	_case_pkg_001()
	_case_pkg_002()
	_case_pkg_003()
	_case_pkg_004()
	_case_pkg_005()
	_case_proto_001()
	_case_proto_002()
	_case_builtin_001()
	_case_builtin_002()
	_case_det_001()
	_case_save_001()
	_case_save_002()
	_case_package_survives()
	_case_file_backend()
	_case_off_003()
	_case_no_clock()
	_case_ux_001()
	_case_save_clock()
	_case_landing_without_saves()
	_case_shell_refusal()
	_case_import_control()
	_case_font_coverage()
	_case_slot_layout()
	_case_version()
	_case_locale()
	_case_i18n()
	_case_i18n_shipped()
	_case_format()
	_case_ledger()
	_case_assets()

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
		["V-04 spec window", _package("spec-too-new", {"specVersion": "3.5.0"}), "V-04"],
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
	# Step 4 of the case: save the end scene to slot 1, then resume from the stored
	# bytes. B3 deferred this step to B4, B4 shipped the store and asserted only the
	# generic save cases, so the step is closed here — the exit line asks for the
	# resumed session to start at the saved end node, not just for a slot to accept
	# a write.
	MemoryBackend.reset()
	var entry: Dictionary = loader.registry.entry("sanguo")
	var store := SaveStore.new()
	var saved_node := session.current
	var written := store.write(entry, 1, session.snapshot(), "三国")
	_check("TC-BUILTIN-001: the end scene saves to slot 1", bool(written.get("ok", false)), str(written))
	var read_back := store.read(entry, 1)
	var resumed: Session = null
	if bool(read_back.get("ok", false)):
		resumed = store.resume(entry, read_back["payload"])
	_check(
		"TC-BUILTIN-001: the resumed session starts at the saved end node",
		resumed != null and resumed.current == saved_node,
		"resumed %s, saved %s" % [resumed.current if resumed != null else "-", saved_node],
	)
	_check(
		"TC-BUILTIN-001: the resumed session is still at the end",
		resumed != null and resumed.finished and resumed.current == session.current,
	)


func _case_builtin_002() -> void:
	_section("TC-BUILTIN-002 Xiuxian plays its segment and reports progress")
	var package := FileAccess.get_file_as_bytes(BUILTIN_XIUXIAN)
	if package.is_empty():
		_failures.append("staged package missing at %s; run infra/stage_builtin.py" % BUILTIN_XIUXIAN)
		return
	var loader := PackageLoader.new()
	var result := loader.import_bytes(package, _context())
	_check(
		"TC-BUILTIN-002: the shipped package installs",
		result["status"] == "installed",
		"%s %s" % [String(result.get("code", "-")), String(result.get("message", ""))],
	)
	if result["status"] != "installed":
		return
	var entry: Dictionary = loader.registry.entry("xiuxian")
	_check(
		"TC-BUILTIN-002: it rides the linear protocol, not the one Sanguo uses",
		String(entry["manifest"]["protocol"]) == "linear@1",
		String(entry["manifest"]["protocol"]),
	)
	var session := Session.create(entry, {"start_counter": 1})
	var view: Dictionary = session.start()
	_check("TC-BUILTIN-002: the entry scene shows text", String(view.get("text", "")) != "")
	var progress: Dictionary = view.get("progress", {})
	_check("TC-BUILTIN-002: the progress readout is present", not progress.is_empty(), str(view.keys()))
	_check(
		"TC-BUILTIN-002: the readout knows the length of the segment",
		int(progress.get("nodes", 0)) >= 4,
		str(progress),
	)
	var steps: Array = [int(progress.get("steps", 0))]
	var realms: Array = []
	while not bool(view.get("finished", false)):
		var offered: Array = view.get("choices", [])
		if offered.is_empty():
			break
		view = session.choose(0)
		progress = view.get("progress", {})
		steps.append(int(progress.get("steps", 0)))
		var state: Dictionary = view.get("state", {})
		if state.has("realm"):
			realms.append(String(state["realm"]))
	_check("TC-BUILTIN-002: the segment is playable to its end", bool(view.get("finished", false)), str(steps))
	_check("TC-BUILTIN-002: the end node shows its text", String(view.get("text", "")) != "")
	_check("TC-BUILTIN-002: the end node offers nothing more", (view.get("choices", []) as Array).is_empty())
	var growing := steps.size() >= 3
	for index in range(1, steps.size()):
		if int(steps[index]) <= int(steps[index - 1]):
			growing = false
	_check("TC-BUILTIN-002: progress grows with every step", growing, str(steps))
	_check(
		"TC-BUILTIN-002: the realm label follows the choices",
		realms.size() >= 3 and String(realms[realms.size() - 1]) == "元婴",
		str(realms),
	)
	MemoryBackend.reset()
	var store := SaveStore.new()
	var saved_node := session.current
	var written := store.write(entry, 1, session.snapshot(), "修仙")
	_check("TC-BUILTIN-002: the segment saves to slot 1", bool(written.get("ok", false)), str(written))
	var read_back := store.read(entry, 1)
	var resumed: Session = null
	if bool(read_back.get("ok", false)):
		resumed = store.resume(entry, read_back["payload"])
	_check(
		"TC-BUILTIN-002: resuming returns to the saved node",
		resumed != null and resumed.current == saved_node,
		"resumed %s, saved %s" % [resumed.current if resumed != null else "-", saved_node],
	)
	var shell := _shell()
	shell.open_plugins()
	_check(
		"TC-BUILTIN-002: the list shows both built-in genres",
		shell.builtin_ids.has("xiuxian") and shell.builtin_ids.has("sanguo"),
		str(shell.builtin_ids),
	)
	shell.start_plugin("xiuxian")
	_check(
		"TC-BUILTIN-002: the progress readout is on screen",
		shell.visible_text().contains("step 1/"),
		shell.visible_text(),
	)
	shell.choose(0)
	_check(
		"TC-BUILTIN-002: the readout moves with the player",
		shell.visible_text().contains("step 2/"),
		shell.visible_text(),
	)


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
		"specVersion": "2.0.0",
		"kind": "bundle",
		"requires": [],
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
	binary_files: Dictionary = {},
) -> PackedByteArray:
	## Builds a fixture zip in res:// and returns its bytes. `extra_files` are
	## paths that exist in the zip with dummy content; `binary_files` maps a path
	## to the exact bytes it should carry (a picture or a sound needs real bytes,
	## a placeholder string would only test the failure path).
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
	for extra_path in binary_files:
		_write_entry(packer, String(extra_path), binary_files[extra_path])
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


# --- shell cases (B5a) -------------------------------------------------------
#
# The shell is driven through its own methods, not through synthetic clicks: a
# click is a button wiring, and the wiring is one line per button. What the case
# proves is the path a player walks and what they see at each step, which is what
# TC-UX-001 asks for.

func _shell() -> Shell:
	var shell := Shell.new()
	# The sandbox cannot write user://, so staging goes to the fixture folder the
	# other cases already use. The shipped default stays user:// for the browser.
	shell.work_dir = FIXTURE_DIR
	# Saves in the suite go to the memory backend: a file backend would carry a
	# slot from one case into the next and make "three empty slots" untrue.
	MemoryBackend.reset()
	shell.saves = SaveStore.new(MemoryBackend.new())
	# Imported packs go to memory too: a file backend would carry the pack from
	# this case into every later one that lists the installed packs.
	shell.packages = PackageStore.new(MemoryBackend.new())
	shell._ready()
	return shell


func _case_file_backend() -> void:
	# The backend the browser actually uses. A second instance over the same
	# folder is what a page reload looks like to the stores, so this is the
	# headless half of TC-OFF-002: the bytes are on disk, not in a variable.
	_section("TC-OFF-002 saves survive a store that was rebuilt from the same folder")
	var root := "%s/store-case" % FIXTURE_DIR
	_clear_dir(root)
	var first := FileBackend.new(root)
	_check("TC-OFF-002: a write reports success", first.write("save:sanguo:1", "payload"))
	_check("TC-OFF-002: the key is listed", first.keys().has("save:sanguo:1"), str(first.keys()))
	var second := FileBackend.new(root)
	_check("TC-OFF-002: a fresh backend reads it back", second.read("save:sanguo:1") == "payload")
	var store := SaveStore.new(second)
	_check("TC-OFF-002: a store built over the folder sees the key", store.backend.keys().has("save:sanguo:1"))
	_check("TC-OFF-002: erase removes it", second.erase("save:sanguo:1") and not second.has("save:sanguo:1"))
	# A key with a separator must not escape the folder.
	_check("TC-OFF-002: slashes in a key stay inside the folder", first.write("a/b", "x") and first.keys().has("a/b"))
	_clear_dir(root)


func _clear_dir(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name in directory.get_files():
		DirAccess.remove_absolute("%s/%s" % [path, name])



func _case_ux_001() -> void:
	_section("TC-UX-001 a first-time player reaches a game without instructions")
	var shell := _shell()
	_check("TC-UX-001: the app opens on the landing screen", shell.screen_name() == "landing")
	_check("TC-UX-001: the landing screen names the product", shell.visible_text().contains("Lethebar"))
	# The way in is `New game`, and the stories it leads to are named the way a
	# player reads them: five first-time players asked what game this was while
	# the pack list showed `sanguo — turn_based@1, 0.1.0`.
	shell.open_plugins()
	# The title now follows the interface language: the pack carries `三国` and
	# `Three Kingdoms` in its manifest, and the player reads whichever one matches
	# the language the rest of the screen is in.
	var sanguo_title := "三国" if Locale.current() == "zh-CN" else "Three Kingdoms"
	_check("TC-UX-001: new game lists a story by name", shell.visible_text().contains(sanguo_title), shell.visible_text())
	_check(
		"TC-UX-001: the pack list hides the protocol name",
		not shell.visible_text().contains("turn_based"),
		shell.visible_text(),
	)
	_check("TC-UX-001: the shipped pack is listed", shell.builtin_ids.has("sanguo"), str(shell.builtin_ids))
	var view := shell.start_plugin("sanguo")
	_check("TC-UX-001: picking a pack starts a session", shell.screen_name() == "session")
	_check("TC-UX-001: the first scene shows its text", String(view.get("text", "")) != "")
	_check("TC-UX-001: the first scene offers a next step", view.get("choices", []).size() >= 1)
	var first_node := String(view.get("node", ""))
	view = shell.choose(0)
	_check("TC-UX-001: a choice advances the scene", String(view.get("node", "")) != first_node)
	# The readout follows the mechanic's state, so it is asserted after the first
	# choice has moved power, not on the entry scene where nothing has happened yet.
	_check("TC-UX-001: the mechanic readout is visible", shell.visible_text().contains("power"), shell.visible_text())
	shell.save_to(1)
	_check("TC-UX-001: saving reports the slot", shell.visible_text().contains("Saved to slot 1"), shell.visible_text())
	var saved_node := String(shell.current_view().get("node", ""))
	shell.choose(0)
	shell.load_from(1)
	_check(
		"TC-UX-001: loading the slot restores the saved node",
		String(shell.current_view().get("node", "")) == saved_node,
		"%s vs %s" % [String(shell.current_view().get("node", "")), saved_node],
	)
	_check("TC-UX-001: the restored scene is a session screen", shell.screen_name() == "session")
	# The landing screen is a way in, not a menu: one line says what this is and
	# `New game` leads to the stories. `Continue` appears once something is saved,
	# and it goes to the saves themselves rather than asking which pack.
	shell.show_landing()
	_check(
		"TC-UX-001: the landing screen says what this is",
		shell.visible_text().contains("Short text stories"),
		shell.visible_text(),
	)
	_check(
		"TC-UX-001: the landing screen offers a new game",
		shell.visible_text().contains("New game"),
		shell.visible_text(),
	)
	_check(
		"TC-UX-001: the landing screen offers continue when a slot is saved",
		shell.visible_text().contains("Continue"),
		shell.visible_text(),
	)
	var loads := shell.show_loads()
	_check("TC-UX-001: continue opens the saves", shell.screen_name() == "loads")
	var saved_title := "三国" if Locale.current() == "zh-CN" else "Three Kingdoms"
	_check(
		"TC-UX-001: a saved slot is named by its story",
		shell.visible_text().contains(saved_title),
		shell.visible_text(),
	)
	var resumed := shell.resume_slot("sanguo", 1)
	_check(
		"TC-UX-001: continue resumes at the saved scene",
		String(resumed.get("node", "")) == saved_node,
		"%s vs %s" % [String(resumed.get("node", "")), saved_node],
	)
	_check("TC-UX-001: continue lands on a session screen", shell.screen_name() == "session")


func _case_save_clock() -> void:
	# The payload records UTC. The list used to print that UTC time of day, so a
	# save made at 14:20 in UTC+8 read `06:20` — the player's own clock is what it
	# must show. Asserting against the machine clock catches a regression to UTC on
	# any machine that is not already on UTC.
	_section("TC-UX-001 the save list shows the player's clock")
	var shell := _shell()
	shell.start_plugin("sanguo")
	shell.save_to(1)
	var row: Dictionary = {}
	for candidate in shell._saves_index():
		if String(candidate.get("plugin", "")) == "sanguo" and int(candidate.get("slot", 0)) == 1:
			row = candidate
	_check("TC-UX-001: the saved slot is listed", not row.is_empty())
	var clock := shell._local_clock(String(row.get("savedAt", "")))
	_check("TC-UX-001: the listed clock parses", clock != "", String(row.get("savedAt", "")))
	var now := Time.get_datetime_string_from_system(false).substr(11, 5)
	var drift: int = absi(_minutes_of(clock) - _minutes_of(now))
	_check(
		"TC-UX-001: the listed clock is local time",
		drift <= 1,
		"%s (local now %s)" % [clock, now],
	)
	_check(
		"TC-UX-001: the continue row shows that clock",
		shell._save_label(row).contains(clock),
		shell._save_label(row),
	)


func _minutes_of(clock: String) -> int:
	var parts := clock.split(":")
	if parts.size() != 2:
		return -1
	return int(parts[0]) * 60 + int(parts[1])


func _case_landing_without_saves() -> void:
	# The other half of the `Continue` rule: a first visit must not show a button
	# that leads nowhere.
	_section("TC-UX-001 the landing screen hides continue when nothing is saved")
	var shell := _shell()
	shell.show_landing()
	_check(
		"TC-UX-001: a fresh browser has no continue button",
		not shell.visible_text().contains("Continue"),
		shell.visible_text(),
	)
	_check(
		"TC-UX-001: a fresh browser still offers a new game",
		shell.visible_text().contains("New game"),
		shell.visible_text(),
	)


func _case_shell_refusal() -> void:
	_section("TC-PKG-001 a refused package leaves the shell usable")
	var shell := _shell()
	var view := shell.try_import("this is not a zip".to_utf8_buffer())
	_check("TC-PKG-001: the shell shows a refusal screen", shell.screen_name() == "notice")
	_check("TC-PKG-001: the refusal carries its V- code", String(view.get("code", "")) == "V-01", str(view.get("code", "")))
	shell.open_plugins()
	_check("TC-PKG-001: the packs are still listed after a refusal", shell.builtin_ids.has("sanguo"))
	shell.start_plugin("sanguo")
	_check("TC-PKG-001: a pack still starts after a refusal", shell.screen_name() == "session")


func _case_import_control() -> void:
	# The player's half of TC-PKG-001: the pack list has an install control, and
	# the bytes it hands over come back as base64 — the same shape the injected
	# file input produces in the browser, so this covers the decode step too.
	_section("TC-PKG-001 a pack chosen from a file is validated and installed")
	var shell := _shell()
	shell.open_plugins()
	_check(
		"TC-PKG-001: the pack list offers an install control",
		shell.visible_text().contains("Install a pack"),
		shell.visible_text(),
	)
	var bytes := _package("import-fixture", {"id": "imported-pack", "name": "Imported Pack"})
	var view := shell.install_from_base64(Marshalls.raw_to_base64(bytes))
	_check("TC-PKG-001: a chosen file installs its pack", shell.builtin_ids.has("imported-pack"), str(shell.builtin_ids))
	_check("TC-PKG-001: installing starts the pack", shell.screen_name() == "session")
	_check("TC-PKG-001: the imported pack is playable", String(view.get("text", "")) != "", str(view))
	var refusal := shell.install_from_base64(Marshalls.raw_to_base64("not a zip".to_utf8_buffer()))
	_check(
		"TC-PKG-001: a file that is not a package is refused with its code",
		shell.screen_name() == "notice" and String(refusal.get("code", "")) == "V-01",
		"%s / %s" % [shell.screen_name(), String(refusal.get("code", ""))],
	)
	shell.open_plugins()
	_check(
		"TC-PKG-001: an installed pack survives a refused file",
		shell.builtin_ids.has("imported-pack") and shell.builtin_ids.has("sanguo"),
		str(shell.builtin_ids),
	)


func _case_font_coverage() -> void:
	# A font without the glyph draws a box. Nothing in the suite looks at pixels,
	# so the coverage is asserted on characters instead: every character a shipped
	# pack can show, and every character the shell puts on screen, has to exist in
	# the font the project ships. Without this, the browser build rendered every
	# Chinese string as "no glyph" boxes while all the string assertions passed.
	_section("TC-BUILTIN-001 every character on screen has a glyph")
	var font := _shipped_font()
	_check("the project ships a font for pack text", font != null, "no gui/theme/custom_font")
	if font == null:
		return
	var list_path := "res://builtin/chars.txt"
	_check("the staged packs carry their character list", FileAccess.file_exists(list_path), list_path)
	if not FileAccess.file_exists(list_path):
		return
	var characters := FileAccess.get_file_as_string(list_path)
	var missing := ""
	var seen := {}
	for index in characters.length():
		var code := characters.unicode_at(index)
		if code <= 0x20:
			continue
		if not font.has_char(code) and not seen.has(code):
			seen[code] = true
			missing += char(code)
	_check("every staged pack character has a glyph", missing == "", "missing: %s" % missing)
	var shell := _shell()
	var screens := [shell.visible_text()]
	shell.open_plugins()
	screens.append(shell.visible_text())
	shell.start_plugin("sanguo")
	screens.append(shell.visible_text())
	shell.choose(0)
	screens.append(shell.visible_text())
	shell.open_saves()
	screens.append(shell.visible_text())
	var ui_missing := ""
	var ui_seen := {}
	for screen in screens:
		var text := String(screen)
		for index in text.length():
			var code := text.unicode_at(index)
			if code <= 0x20:
				continue
			if not font.has_char(code) and not ui_seen.has(code):
				ui_seen[code] = true
				ui_missing += char(code)
	_check("every character the shell shows has a glyph", ui_missing == "", "missing: %s" % ui_missing)
	var samples := {"BMP": 0x4E00, "extension A": 0x3400, "extension A upper": 0x3FFF}
	for label in samples:
		var code: int = samples[label]
		_check(
			"the font has a glyph for U+%04X (%s)" % [code, label],
			font.has_char(code),
			"U+%04X is missing from the shipped font" % code
		)


func _case_slot_layout() -> void:
	# A manual run in a narrow window found what no assertion covered: the slot
	# label asked for the width of the whole sentence, so Save and Load were
	# pushed past the right edge and the player could not save at all. The
	# property asserted here is geometry, not text: every slot row has to fit
	# inside the window, and the stored preview has to stay short enough to fit.
	_section("TC-UX-001 a slot row fits the window, buttons included")
	var shell := _shell()
	shell.start_plugin("sanguo")
	shell.choose(0)
	shell.save_to(1)
	_check("TC-UX-001: the slots screen is up", shell.screen_name() == "saves", shell.screen_name())
	var rows: Array = shell.saves.slots(shell.entry)
	var preview := String(rows[0].get("preview", "")) if rows.size() > 0 else ""
	_check("TC-UX-001: a saved slot carries a preview", preview != "", str(rows))
	_check(
		"TC-UX-001: the stored preview is clipped",
		preview.length() <= shell.PREVIEW_CHARS + 1,
		"%d characters: %s" % [preview.length(), preview]
	)
	var budget := shell._slot_text_width()
	var button_rows := 0
	for child in shell._options.get_children():
		if not child is HBoxContainer:
			continue
		button_rows += 1
		var row := child as HBoxContainer
		var label := row.get_child(0) as Label
		_check(
			"TC-UX-001: the slot label wraps instead of demanding one line",
			label != null and label.autowrap_mode != TextServer.AUTOWRAP_OFF,
			"autowrap_mode=%s" % (label.autowrap_mode if label != null else "no label")
		)
		var label_width := label.get_combined_minimum_size().x if label != null else -1.0
		_check(
			"TC-UX-001: the slot label takes the budgeted width, not the sentence's",
			label_width <= budget + 1.0,
			"label asks %s px, budget is %s px" % [label_width, budget]
		)
		_check(
			"TC-UX-001: the slot row fits the budgeted width",
			row.get_combined_minimum_size().x <= budget + shell.SLOT_BUTTONS_WIDTH + 16.0,
			"row asks %s px" % row.get_combined_minimum_size().x
		)
		var buttons := 0
		for part in row.get_children():
			if part is Button:
				buttons += 1
		_check("TC-UX-001: the row keeps both of its buttons", buttons == 2, "%d button(s)" % buttons)
	_check("TC-UX-001: all three slots are laid out", button_rows == 3, "%d row(s)" % button_rows)


func _case_version() -> void:
	# The product version had no single home: it lived in the tag and in two
	# READMEs, so a release could ship three numbers that disagreed. The shell
	# now reads `application/config/version`, and this case pins the two things
	# that matter: the shell reports what the project sets, and the shape is
	# three dot-separated numbers, which is what every version string here uses.
	_section("REQ-017: the shell reports the product version")
	var shell := _shell()
	var configured := String(ProjectSettings.get_setting("application/config/version", ""))
	_check("REQ-017: the project sets application/config/version", configured != "", configured)
	_check(
		"REQ-017: the shell reports the configured version",
		shell.version_string() == configured,
		"shell says %s, project says %s" % [shell.version_string(), configured]
	)
	var parts := shell.version_string().split(".")
	var numeric := parts.size() == 3
	for part in parts:
		if not part.is_valid_int() or part.is_empty():
			numeric = false
	_check(
		"REQ-017: the version is three dot-separated numbers",
		numeric,
		shell.version_string()
	)


func _case_locale() -> void:
	## B8: the interface speaks English and Chinese. The assertion that matters
	## most is the last one — no Chinese literal survives in the interface code —
	## because that is what stops the next batch from quietly writing one again.
	Locale.reload()
	Locale.set_current("en")
	_check(
		"B8: English is the default interface language",
		Locale.current() == "en",
		Locale.current()
	)
	_check(
		"B8: English strings come from the catalogue",
		Locale.text("ui.new_game") == "New game",
		Locale.text("ui.new_game")
	)
	Locale.set_current("zh-CN")
	_check(
		"B8: Chinese strings come from the catalogue",
		Locale.text("ui.new_game") == "新游戏",
		Locale.text("ui.new_game")
	)
	var shell := _shell()
	shell.show_landing()
	_check(
		"B8: the landing screen switches to Chinese",
		shell.visible_text().contains("新游戏"),
		shell.visible_text()
	)
	Locale.reload()
	_check(
		"B8: the chosen language survives a restart",
		Locale.current() == "zh-CN",
		Locale.current()
	)
	Locale.set_current("en")
	var offenders := _chinese_in("res://render")
	_check(
		"B8: no Chinese literal is left in the interface code",
		offenders.is_empty(),
		", ".join(offenders)
	)


func _case_i18n() -> void:
	## B10. The package decides what it says; the engine decides which language it
	## says it in. Every step of the fallback chain is asserted, because a silent
	## fallback is what a player would meet as a language switch mid-scene.
	_section("TC-BUILTIN-001 a package carries its text in two languages")
	var nodes := {
		"nodes": [
			{"id": "n1", "text": "一个中文节点。", "choices": [{"label": "向左", "next": "n1"}]},
		]
	}
	var english := JSON.stringify({
		"n1": {"text": "An English node.", "choices": ["Go left"]},
	}, "\t").to_utf8_buffer()
	var bilingual := _package(
		"i18n-ok",
		{
			"id": "bilingual",
			"defaultLocale": "zh-CN",
			"locales": ["en"],
			"names": {"zh-CN": "双语", "en": "Bilingual"},
		},
		[],
		[],
		nodes,
		{},
		{"data/i18n/en.json": english}
	)
	var installed := PackageLoader.new().import_bytes(bilingual, _context())
	_check(
		"TC-PKG-001: a package that declares a locale installs",
		installed["status"] == "installed",
		String(installed.get("message", ""))
	)
	var entry: Dictionary = installed.get("entry", {})
	var english_view := Session.create(entry, {"locale": "en"}).start()
	_check(
		"TC-BUILTIN-001: the scene reads in English",
		String(english_view.get("text", "")) == "An English node.",
		String(english_view.get("text", ""))
	)
	_check(
		"TC-BUILTIN-001: the choices read in English",
		String(english_view["choices"][0]["label"]) == "Go left",
		String(english_view["choices"][0]["label"])
	)
	_check(
		"TC-BUILTIN-001: the default locale reads as written",
		String(Session.create(entry, {"locale": "zh-CN"}).start()["text"]) == "一个中文节点。",
		String(Session.create(entry, {"locale": "zh-CN"}).start()["text"])
	)
	var unlisted: Dictionary = Session.create(entry, {"locale": "fr"}).start()
	_check(
		"TC-BUILTIN-001: an unlisted locale falls back to the package text",
		String(unlisted.get("text", "")) == "一个中文节点。",
		String(unlisted.get("text", ""))
	)

	_section("TC-PKG-001 a declared language that is only half there is refused")
	var partial := JSON.stringify({
		"n1": {"text": "An English node.", "choices": []},
	}, "\t").to_utf8_buffer()
	var half := PackageLoader.new().import_bytes(
		_package(
			"i18n-partial",
			{"id": "half", "defaultLocale": "zh-CN", "locales": ["en"]},
			[], [], nodes, {}, {"data/i18n/en.json": partial}
		),
		_context()
	)
	_check(
		"V-22 partial cover",
		half["status"] == "rejected" and half["code"] == "V-22",
		"got %s/%s" % [half["status"], half.get("code", "-")]
	)
	var absent := PackageLoader.new().import_bytes(
		_package(
			"i18n-missing",
			{"id": "absent", "defaultLocale": "zh-CN", "locales": ["en"]},
			[], [], nodes
		),
		_context()
	)
	_check(
		"V-22 declared but missing",
		absent["status"] == "rejected" and absent["code"] == "V-22",
		"got %s/%s" % [absent["status"], absent.get("code", "-")]
	)
	var unsupported := PackageLoader.new().import_bytes(
		_package("i18n-fr", {"id": "french", "defaultLocale": "fr"}), _context()
	)
	_check(
		"V-22 unsupported locale",
		unsupported["status"] == "rejected" and unsupported["code"] == "V-22",
		"got %s/%s" % [unsupported["status"], unsupported.get("code", "-")]
	)
	var solo: Dictionary = Session.create(
		PackageLoader.new().import_bytes(
			_package("i18n-none", {"id": "mono"}), _context()
		).get("entry", {}),
		{"locale": "en"}
	).start()
	_check(
		"TC-PKG-001: a package with one language still plays in it",
		String(solo.get("text", "")) == "A node.",
		String(solo.get("text", ""))
	)


func _case_i18n_shipped() -> void:
	## B13. The mechanism was proved with fixtures; this proves the pack a player
	## actually meets also speaks English. A translation that misses one node or
	## one label is refused by V-22 at install time, so "it installs" is the first
	## assertion, not a formality.
	_section("TC-I18N-001 the shipped Xiuxian pack speaks English")
	var package := FileAccess.get_file_as_bytes(BUILTIN_XIUXIAN)
	if package.is_empty():
		_failures.append("staged package missing at %s; run infra/stage_builtin.py" % BUILTIN_XIUXIAN)
		return
	var loader := PackageLoader.new()
	var result := loader.import_bytes(package, _context())
	_check(
		"TC-I18N-001: the shipped pack passes the locale rule",
		result["status"] == "installed",
		"%s %s" % [String(result.get("code", "-")), String(result.get("message", ""))],
	)
	if result["status"] != "installed":
		return
	var entry: Dictionary = loader.registry.entry("xiuxian")
	var english := Session.create(entry, {"locale": "en"}).start()
	var english_text := String(english.get("text", ""))
	_check(
		"TC-I18N-001: the entry scene reads in English",
		not english_text.is_empty() and _chinese_chars(english_text).is_empty(),
		english_text,
	)
	var labels: Array = []
	for choice in english.get("choices", []):
		labels.append(String(choice.get("label", "")))
	var chinese_labels := []
	for label in labels:
		if not _chinese_chars(String(label)).is_empty():
			chinese_labels.append(label)
	_check(
		"TC-I18N-001: every entry choice reads in English",
		not labels.is_empty() and chinese_labels.is_empty(),
		"labels %s, still Chinese %s" % [str(labels), str(chinese_labels)],
	)
	var chinese := Session.create(entry, {"locale": "zh-CN"}).start()
	_check(
		"TC-I18N-001: a Chinese reader still meets the shipped text",
		not _chinese_chars(String(chinese.get("text", ""))).is_empty(),
		String(chinese.get("text", "")),
	)


func _chinese_chars(text: String) -> Array:
	## The shipped-text check needs "does this string contain an ideograph", not
	## "does this file contain one"; the file scanner below answers the other
	## question and returns offsets.
	var found := []
	for index in text.length():
		var code := text.unicode_at(index)
		if code >= 0x4E00 and code <= 0x9FFF:
			found.append(text.substr(index, 1))
	return found


func _chinese_in(dir_path: String) -> Array:
	## Character-level, not word-level: any CJK ideograph in a script under
	## `res://render` means a sentence was written into the code again.
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ["missing " + dir_path]
	for name in dir.get_files():
		if not name.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string(dir_path.path_join(name))
		for index in text.length():
			var code := text.unicode_at(index)
			if code >= 0x4E00 and code <= 0x9FFF:
				out.append("%s at %d" % [name, index])
				break
	return out


func _shipped_font() -> Font:
	## The font the built build actually renders with: the project setting, not a
	## hard-coded path, so removing it fails the check instead of silently passing.
	var path := String(ProjectSettings.get_setting("gui/theme/custom_font", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Font


func _case_format() -> void:
	## B15. ADR-0007: a package says which format it speaks and what it needs
	## before it can be played. The five acceptance lines are the six checks
	## below; the two refusals are the ones a player would otherwise meet as a
	## story that cannot be finished.
	_section("TC-FMT-001 a package declares its format and what it requires")
	var plain := PackageLoader.new().import_bytes(
		_package("fmt-bundle", {"id": "fmt-bundle"}), _context()
	)
	_check(
		"TC-FMT-001: a 2.0.0 bundle with no requirements installs",
		plain.get("status", "") == "installed",
		String(plain.get("message", ""))
	)

	var no_layer := PackageLoader.new().import_bytes(
		_package("fmt-no-layer", {"id": "fmt-no-layer", "kind": "layer"}), _context()
	)
	_check(
		"TC-FMT-001: kind layer without a layer name is refused with V-23",
		String(no_layer.get("code", "")) == "V-23",
		String(no_layer.get("message", ""))
	)

	var bad_layer := PackageLoader.new().import_bytes(
		_package("fmt-bad-layer", {"id": "fmt-bad-layer", "kind": "layer", "layer": "weather"}),
		_context()
	)
	_check(
		"TC-FMT-001: an unknown layer name is refused with V-23",
		String(bad_layer.get("code", "")) == "V-23",
		String(bad_layer.get("message", ""))
	)

	var missing := PackageLoader.new().import_bytes(
		_package("fmt-needs", {
			"id": "fmt-needs",
			"requires": [{"id": "ghost", "version": ">=1.0.0 <2.0.0"}],
		}),
		_context()
	)
	_check(
		"TC-FMT-001: a requirement nobody installed is refused with V-24",
		String(missing.get("code", "")) == "V-24",
		String(missing.get("message", ""))
	)

	var loader := PackageLoader.new()
	loader.import_bytes(
		_package("fmt-layer", {"id": "fmt-layer", "kind": "layer", "layer": "mod"}), _context()
	)
	var wrong_range := loader.import_bytes(
		_package("fmt-range", {
			"id": "fmt-range",
			"requires": [{"id": "fmt-layer", "version": ">=2.0.0 <3.0.0"}],
		}),
		_context()
	)
	var range_message := String(wrong_range.get("message", ""))
	_check(
		"TC-FMT-001: a requirement outside its range is refused with V-24",
		String(wrong_range.get("code", "")) == "V-24",
		range_message
	)
	_check(
		"TC-FMT-001: the refusal names the package and the installed version",
		range_message.contains("fmt-layer") and range_message.contains("1.0.0"),
		range_message
	)

	var satisfied := loader.import_bytes(
		_package("fmt-ok", {
			"id": "fmt-ok",
			"requires": [{"id": "fmt-layer", "version": ">=1.0.0 <2.0.0"}],
		}),
		_context()
	)
	_check(
		"TC-FMT-001: a satisfiable requirement installs",
		satisfied.get("status", "") == "installed",
		String(satisfied.get("message", ""))
	)

	var legacy := PackageLoader.new().import_bytes(
		_package("fmt-legacy", {"id": "fmt-legacy", "specVersion": "1.0.0"}), _context()
	)
	_check(
		"TC-FMT-001: a 1.0.0 package still installs",
		legacy.get("status", "") == "installed",
		String(legacy.get("message", ""))
	)
	var warning_codes: Array = []
	for warning in legacy.get("warnings", []):
		warning_codes.append(String(warning.get("code", "")))
	_check(
		"TC-FMT-001: it carries one W-01 warning naming the format",
		warning_codes == ["W-01"],
		", ".join(warning_codes)
	)



func _case_ledger() -> void:
	_section("TC-LEDGER-001 a package declares its numbers and their bounds")
	var nodes := {
		"nodes": [
			{"id": "n1", "text": "One.", "choices": [{"label": "Go", "next": "n2", "effects": [{"power": {"add": 10}}]}]},
			{"id": "n2", "text": "Two.", "choices": []},
		],
	}
	var ledger := {
		"resources": [
			{"id": "power", "label": "power", "init": 3, "min": 0, "max": 5},
		],
	}
	var rules := {"rules": []}
	var entry: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"ledger-basic",
			{"id": "ledger-basic"},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(rules).to_utf8_buffer(),
			},
		),
		_context()
	)["entry"]
	_check("TC-LEDGER-001: the package with a ledger installs", not entry.is_empty(), str(entry))
	var session := Session.create(entry)
	session.start()
	_check(
		"TC-LEDGER-001: a declared resource starts at its init value",
		float(session.state.get("power", -1.0)) == 3.0,
		str(session.state)
	)
	session.choose(0)
	_check(
		"TC-LEDGER-001: an effect above max is clamped, not refused",
		float(session.state.get("power", -1.0)) == 5.0,
		str(session.state)
	)

	var undeclared_rules := {"rules": [{"when": {"key": "gold", "op": "gte", "value": 1}, "set": {"power": {"add": 1}}}]}
	var refused := PackageLoader.new().import_bytes(
		_package(
			"ledger-undeclared",
			{"id": "ledger-undeclared"},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(undeclared_rules).to_utf8_buffer(),
			},
		),
		_context()
	)
	_check(
		"TC-LEDGER-001: a rule that names an undeclared resource is refused with V-14",
		String(refused.get("code", "")) == "V-14" and String(refused.get("message", "")).contains("gold"),
		"%s %s" % [String(refused.get("code", "-")), String(refused.get("message", ""))]
	)

	# A choice moves `power` down to 0; the settlement rule that reads it must run
	# afterwards, or the label would lag one scene behind the number.
	var ordered_nodes := {
		"nodes": [
			{"id": "n1", "text": "One.", "choices": [{"label": "Go", "next": "n2", "effects": [{"power": {"value": 0}}]}]},
			{"id": "n2", "text": "Two.", "choices": []},
		],
	}
	var ordered_state := {
		"resources": [
			{"id": "power", "init": 3, "min": 0, "max": 5},
			{"id": "standing", "init": 2, "min": 0, "max": 2, "labels": {"0": "兵微将寡", "2": "名动诸侯"}},
		],
	}
	var ordered_rules := {"rules": [{"when": {"key": "power", "op": "lte", "value": 0}, "set": {"standing": {"value": 0}}}]}
	var ordered: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"ledger-ordered",
			{"id": "ledger-ordered"},
			[],
			[],
			ordered_nodes,
			{},
			{
				"data/state.json": JSON.stringify(ordered_state).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(ordered_rules).to_utf8_buffer(),
			},
		),
		_context()
	)["entry"]
	var ordered_session := Session.create(ordered)
	var opening := ordered_session.start()
	ordered_session.choose(0)
	_check(
		"TC-LEDGER-001: rules run after the choice effects",
		float(ordered_session.state.get("standing", -1.0)) == 0.0,
		str(ordered_session.state)
	)
	_check(
		"TC-LEDGER-001: a labelled resource reads as its label",
		String(opening.get("labels", {}).get("standing", "")) == "名动诸侯",
		str(opening.get("labels", {}))
	)

	MemoryBackend.reset()
	var store := SaveStore.new()
	var saved := store.write(ordered, 1, ordered_session.snapshot(), "零")
	_check("TC-LEDGER-001: the run saves", saved["ok"], String(saved["message"]))
	var payload: Dictionary = store.read(ordered, 1)["payload"]
	var resumed := SaveStore.new().resume(ordered, payload)
	_check(
		"TC-LEDGER-001: a resumed run reads the numbers it saved",
		resumed != null and is_equal_approx(float(resumed.state.get("power", -1.0)), float(ordered_session.state.get("power", -2.0))),
		"" if resumed == null else str(resumed.state)
	)


func _case_assets() -> void:
	# B9. The spec already said how a picture is read and what happens when it is
	# missing (SDD §8.1 read from memory, §8.2 degrade to a placeholder); nothing
	# drew one, so "shows the text" was the whole promise. These checks are on the
	# scene tree: a texture with a real size, a placeholder when the bytes are
	# absent, and no picture band at all for a pack that ships none.
	_section("TC-ASSET-001 a declared picture reaches a slot")
	var png := _png_bytes(64, 32)
	var wav := _wav_bytes()
	var declared := [
		{"type": "texture", "path": "assets/scene.png", "slot": "scene"},
		{"type": "texture", "path": "assets/face.png", "slot": "portrait"},
		{"type": "audio", "path": "assets/theme.wav", "slot": "audio"},
	]
	var nodes := {
		"nodes": [
			{"id": "n1", "text": "A painted node.", "assets": declared, "choices": []},
		]
	}
	var bytes := _package(
		"assets-ok",
		{"id": "painted", "assets": declared},
		[],
		[],
		nodes,
		{},
		{
			"assets/scene.png": png,
			"assets/face.png": png,
			"assets/theme.wav": wav,
		}
	)
	var shell := _shell()
	shell.try_import(bytes)
	_check(
		"TC-ASSET-001: the package installs and opens its first scene",
		shell.screen_name() == "session",
		shell.screen_name()
	)
	_check("TC-ASSET-001: the picture band is shown", shell._band.visible)
	_check("TC-ASSET-001: the scene slot holds a texture", shell._picture.texture != null)
	_check(
		"TC-ASSET-001: the texture has the size of the file",
		shell._picture.texture != null and shell._picture.texture.get_width() == 64,
		"%d px" % shell._picture.texture.get_width() if shell._picture.texture != null else "none"
	)
	_check("TC-ASSET-001: the portrait slot holds a texture", shell._portrait.texture != null)
	_check(
		"TC-ASSET-001: both slots are reported",
		shell._picture_slots.has("scene") and shell._picture_slots.has("portrait"),
		str(shell._picture_slots)
	)
	_check("TC-ASSET-001: the sound is loaded", shell._audio.stream != null)
	_check(
		"TC-ASSET-001: the sounds are not reported as pictures",
		not shell._picture_slots.has("audio"),
		str(shell._picture_slots)
	)

	# A pack that ships no picture keeps the old layout: the band takes no space,
	# so adding assets to the format did not change text-only books.
	var plain := _package("assets-none", {"id": "plain"}, [], [], {"nodes": [{"id": "n1", "text": "Plain.", "choices": []}]}, {}, {})
	var quiet := _shell()
	quiet.try_import(plain)
	quiet.start_plugin("plain")
	_check("TC-ASSET-001: a pack without pictures hides the band", not quiet._band.visible)
	_check("TC-ASSET-001: a pack without pictures reports no slot", quiet._picture_slots.is_empty(), str(quiet._picture_slots))

	# The degraded path: declared, missing from the zip. Import already warns
	# (V-08); the scene still has to open and show a placeholder rather than
	# dying, and the warning has to reach the session record.
	var missing := _package(
		"assets-missing",
		{"id": "missing", "assets": [{"type": "texture", "path": "assets/absent.png", "slot": "scene"}]},
		[],
		[],
		{"nodes": [{"id": "n1", "text": "Missing.", "assets": [{"type": "texture", "path": "assets/absent.png", "slot": "scene"}], "choices": []}]},
		{},
		{}
	)
	var broken := _shell()
	broken.try_import(missing)
	broken.start_plugin("missing")
	_check("TC-ASSET-001: a missing picture still opens the scene", broken.screen_name() == "session", broken.screen_name())
	_check(
		"TC-ASSET-001: a missing picture becomes a placeholder",
		broken._picture.texture is PlaceholderTexture2D,
		str(broken._picture.texture)
	)
	var warnings: Array = broken.session.warnings if broken.session != null else []
	var placeholder_warning := false
	for warning in warnings:
		if String(warning.get("code", "")) == "R-01":
			placeholder_warning = true
	_check("TC-ASSET-001: the placeholder is reported once", placeholder_warning, str(warnings))


func _png_bytes(width: int, height: int) -> PackedByteArray:
	## A real PNG, not a placeholder string: the point is to exercise the decoder.
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.8))
	return image.save_png_to_buffer()


func _wav_bytes() -> PackedByteArray:
	## A tenth of a second of 440 Hz, written by hand: the engine's decoder has to
	## accept real WAV bytes, and generating them here keeps the fixture readable.
	var rate := 22050
	var samples := 2205
	var data := PackedByteArray()
	data.resize(samples * 2)
	for index in samples:
		var value := int(sin(TAU * 440.0 * float(index) / float(rate)) * 8000.0)
		data.encode_s16(index * 2, value)
	var header := PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952)  # RIFF
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157)  # WAVE
	header.encode_u32(12, 0x20746D66)  # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1)  # PCM
	header.encode_u16(22, 1)  # mono
	header.encode_u32(24, rate)
	header.encode_u32(28, rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164)  # data
	header.encode_u32(40, data.size())
	return header + data

