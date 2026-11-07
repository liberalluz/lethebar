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
const BUILTIN_JIANGHU := "res://builtin/jianghu.zip"
const BUILTIN_DUEL := "res://builtin/duel.zip"

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
	_case_builtin_003()
	_case_builtin_004()
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
	_case_i18n_labels()
	_case_format()
	_case_ledger()
	_case_turn()
	_case_pools()
	_case_relations()
	_case_clock()
	_case_scene()
	_case_wire()
	_case_writable_relations()
	_case_situation()
	_case_save_flush()
	_case_save_locale()
	_case_capabilities()
	_case_cards()
	_case_card_art()
	_case_hand_layout()
	_case_shuffle()
	_case_collection()
	_case_assembly()
	_case_layers()
	_case_content()
	_case_meta()
	_case_wire3()
	_case_limits()
	_case_boot()
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
		"capabilities": ["text@1", "audio@1"],
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
	_section("TC-BUILTIN-001 Sanguo plays a twenty-four turn run over four resources")
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
	var entry: Dictionary = loader.registry.entry("sanguo")
	var session := Session.create(entry, {"start_counter": 1})
	_check("TC-BUILTIN-001: a Sanguo session starts", session != null)
	if session == null:
		return
	var view := session.start()
	_check("TC-BUILTIN-001: the opening scene shows text", String(view["text"]) != "")
	for key in ["grain", "troops", "coin", "standing"]:
		_check(
			"TC-BUILTIN-001: the run keeps %s" % key,
			(view["state"] as Dictionary).has(key),
			str((view["state"] as Dictionary).keys()),
		)
	_check(
		"TC-BUILTIN-001: the run is budgeted at twenty-four turns",
		int((session.phase as Dictionary).get("turns", 0)) == 24,
		str(session.phase),
	)
	_check(
		"TC-BUILTIN-001: the scene counts down from the budget",
		int((view.get("situation", {}) as Dictionary).get("turnsLeft", -1)) == 24,
		str(view.get("situation", {})),
	)
	_check("TC-BUILTIN-001: the first turn carries the first rank", String(view["rank"]) == "校尉", String(view["rank"]))
	for pair in [[6, "都尉"], [11, "偏将军"], [16, "将军"], [21, "大将军"], [24, "大将军"]]:
		_check(
			"TC-BUILTIN-001: turn %d is ranked %s" % [int(pair[0]), String(pair[1])],
			Phases.rank(session.phase, int(pair[0])) == String(pair[1]),
			Phases.rank(session.phase, int(pair[0])),
		)
	_check(
		"TC-BUILTIN-001: the run can be lost three ways",
		(session.phase.get("fail", []) as Array).size() == 3,
		str((session.phase.get("fail", []) as Array).size()),
	)
	_check(
		"TC-BUILTIN-001: the menu offers the story's actions",
		(view["actions"] as Array).size() == 5,
		str((view["actions"] as Array).size()),
	)
	var grain_before := float((session.state as Dictionary).get("grain", 0.0))
	session.act("farm")
	_check(
		"TC-BUILTIN-001: farming feeds the army",
		float((session.state as Dictionary).get("grain", 0.0)) > grain_before,
		"%f then %f" % [grain_before, float((session.state as Dictionary).get("grain", 0.0))],
	)
	_check("TC-BUILTIN-001: taking an action spends a turn", session.turn == 2, str(session.turn))
	var relation_before := Relations.value(session.factions, "cao", "shao")
	session.act("envoys")
	session.act("envoys")
	_check(
		"TC-BUILTIN-001: sending envoys raises the standing",
		float((session.state as Dictionary).get("standing", 0.0)) >= 3.0,
		str((session.state as Dictionary).get("standing", 0.0)),
	)
	_check(
		"TC-BUILTIN-001: a rule moves Cao against Shao",
		Relations.value(session.factions, "cao", "shao") < relation_before,
		"%f then %f" % [relation_before, Relations.value(session.factions, "cao", "shao")],
	)
	MemoryBackend.reset()
	var store := SaveStore.new()
	var written := store.write(entry, 1, session.snapshot(), "三国")
	_check("TC-BUILTIN-001: a run in progress saves to slot 1", bool(written.get("ok", false)), str(written))
	var read_back := store.read(entry, 1)
	var resumed: Session = null
	if bool(read_back.get("ok", false)):
		resumed = store.resume(entry, read_back["payload"])
	_check(
		"TC-BUILTIN-001: the resumed run keeps the turn",
		resumed != null and resumed.turn == session.turn,
		"resumed %s, saved %d" % [resumed.turn if resumed != null else "-", session.turn],
	)
	_check(
		"TC-BUILTIN-001: the resumed run keeps the resources",
		resumed != null and is_equal_approx(float((resumed.state as Dictionary).get("grain", -1.0)), float((session.state as Dictionary).get("grain", 0.0))),
		str(resumed.state if resumed != null else {}),
	)
	_check(
		"TC-BUILTIN-001: the resumed run keeps the relation",
		resumed != null and is_equal_approx(Relations.value(resumed.factions, "cao", "shao"), Relations.value(session.factions, "cao", "shao")),
		"resumed %f" % [Relations.value(resumed.factions, "cao", "shao") if resumed != null else -999.0],
	)
	var lost := Session.create(entry, {"start_counter": 2})
	lost.start()
	var guard := 0
	while not lost.finished and guard < 30:
		lost.act("recruit")
		guard += 1
	_check("TC-BUILTIN-001: running out of grain ends the run", lost.finished, str(guard))
	_check(
		"TC-BUILTIN-001: the end names the loss",
		String(lost.fail_reason).contains("粮"),
		String(lost.fail_reason),
	)
	var english := Session.create(entry, {"start_counter": 1, "locale": "en"}).start()
	_check(
		"TC-BUILTIN-001: the English run reads English",
		String(english["text"]).begins_with("In the"),
		String(english["text"]).left(48),
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
	var expected := ["drawn", "factions", "finished", "node", "plugin", "pools", "protocol", "rng", "schema", "state", "tick", "turn", "used", "version", "visited"]
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
		"capabilities": ["text@1"],
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
	# The suite is not a first visit: a real `user://welcome.txt` would make the
	# notice assertions depend on which case ran first.
	shell._welcome_seen = true
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
	_check(
		"TC-UX-001: the first scene offers a next step",
		(view.get("choices", []) as Array).size() >= 1 or (view.get("actions", []) as Array).size() >= 1,
	)
	var first_turn := int(shell.session.turn)
	shell.act("farm")
	_check("TC-UX-001: taking a step advances the scene", int(shell.session.turn) == first_turn + 1, str(shell.session.turn))
	# The readout follows the ledger, so it is asserted after the first action has
	# moved a number, not on the entry scene where nothing has happened yet.
	_check("TC-UX-001: the mechanic readout is visible", shell.visible_text().contains("grain"), shell.visible_text())
	shell.save_to(1)
	_check("TC-UX-001: saving reports the slot", shell.visible_text().contains("Saved to slot 1"), shell.visible_text())
	var saved_turn := int(shell.session.turn)
	shell.act("farm")
	shell.load_from(1)
	_check(
		"TC-UX-001: loading the slot restores the saved turn",
		int(shell.session.turn) == saved_turn,
		"%d vs %d" % [int(shell.session.turn), saved_turn],
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
		"TC-UX-001: continue resumes at the saved turn",
		int(resumed.get("turn", -1)) == saved_turn,
		"%d vs %d" % [int(resumed.get("turn", -1)), saved_turn],
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
		_package("fmt-layer", {"id": "fmt-layer", "kind": "layer", "layer": "mod", "target": "fmt-base"}), _context()
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



func _labels_package(name: String, strings: Dictionary) -> PackedByteArray:
	## A run whose labels are all package text: a rank ladder, a labelled
	## resource, an action and a way to lose. The English table describes the same
	## things the package declares, which is what V-22 measures.
	var nodes := {"nodes": [{"id": "n1", "text": "开场。", "choices": []}]}
	var actions := {
		"actions": [
			{"id": "farm", "label": "屯田", "costs": {}, "effects": [{"grain": {"add": 5}}]},
			{"id": "burn", "label": "烧粮", "costs": {}, "effects": [{"grain": {"value": 0}}]},
		],
	}
	var files := {
		"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
		"data/state.json": JSON.stringify({
			"resources": [
				{"id": "grain", "init": 10, "min": 0, "max": 20},
				{"id": "standing", "init": 2, "min": 0, "max": 2, "labels": {"0": "兵微将寡", "2": "名动诸侯"}},
			],
		}).to_utf8_buffer(),
		"data/phases.json": JSON.stringify({
			"turns": 6,
			"ranks": [{"at": 1, "title": "校尉"}, {"at": 4, "title": "将军"}],
			"fail": [{"when": {"key": "grain", "op": "lte", "value": 0}, "reason": "粮草断绝"}],
		}).to_utf8_buffer(),
		"data/i18n/en.json": JSON.stringify({"n1": {"text": "Opening.", "choices": []}, "strings": strings}).to_utf8_buffer(),
	}
	return _package(name, {"id": name, "defaultLocale": "zh-CN", "locales": ["en"]}, [], [], nodes, {}, files)


func _case_i18n_labels() -> void:
	## B36. A run is made of labels: what the menu offers, what your rank is, what
	## a resource is called in words, and why the run ended. The table could only
	## describe node text before this, so an English run read Chinese there.
	_section("TC-I18N-002 the labels a run is made of follow the locale")
	var strings := {
		"action.farm": "Farm",
		"action.burn": "Burn the stores",
		"rank.1": "Captain",
		"rank.4": "General",
		"resource.standing.0": "Bare",
		"resource.standing.2": "Well-off",
		"failure.0": "The grain ran out.",
	}
	var loader := PackageLoader.new()
	var result := loader.import_bytes(_labels_package("labels-run", strings), _context())
	_check(
		"TC-I18N-002: a package whose table covers its labels installs",
		result["status"] == "installed",
		"%s %s" % [String(result.get("code", "-")), String(result.get("message", ""))],
	)
	if result["status"] != "installed":
		return
	var entry: Dictionary = loader.registry.entry("labels-run")

	var english := Session.create(entry, {"locale": "en"}).start()
	var english_view: Dictionary = english
	var english_actions: Array = english_view.get("actions", [])
	_check(
		"TC-I18N-002: the menu reads in the locale it plays in",
		english_actions.size() == 2 and String(english_actions[0].get("label", "")) == "Farm",
		str(english_actions),
	)
	_check(
		"TC-I18N-002: the rank reads in the locale it plays in",
		String(english_view.get("rank", "")) == "Captain",
		String(english_view.get("rank", "")),
	)
	_check(
		"TC-I18N-002: a labelled resource reads in the locale it plays in",
		String(english_view.get("labels", {}).get("standing", "")) == "Well-off",
		str(english_view.get("labels", {})),
	)

	var chinese := Session.create(entry, {"locale": "zh-CN"}).start()
	var chinese_actions: Array = chinese.get("actions", [])
	_check(
		"TC-I18N-002: a locale with no table keeps the package text",
		chinese_actions.size() == 2 and String(chinese_actions[0].get("label", "")) == "屯田",
		str(chinese_actions),
	)

	var losing := Session.create(entry, {"locale": "en"})
	losing.start()
	losing.act("burn")
	_check(
		"TC-I18N-002: the reason a run ended reads in the locale it plays in",
		String(losing.view().get("failReason", "")) == "The grain ran out.",
		String(losing.view().get("failReason", "")),
	)

	# A key the table leaves out is a gap V-22 refuses, so the fallback can only be
	# reached by a table that never passed the checker; the session still must not
	# blank a label.
	var partial: Dictionary = entry.duplicate(true)
	partial["data"]["i18n"]["en"]["strings"].erase("action.farm")
	var fallback := Session.create(partial, {"locale": "en"})
	fallback.start()
	var fallback_actions: Array = fallback.view().get("actions", [])
	_check(
		"TC-I18N-002: a key the table leaves out falls back to the package text",
		fallback_actions.size() == 2 and String(fallback_actions[0].get("label", "")) == "屯田",
		str(fallback_actions),
	)

	var gap_strings := strings.duplicate(true)
	gap_strings.erase("action.burn")
	var refused := PackageLoader.new().import_bytes(_labels_package("labels-gap", gap_strings), _context())
	_check(
		"TC-I18N-002: a table that describes the scene but not the menu is refused",
		refused["status"] != "installed"
			and String(refused.get("code", "")) == "V-22"
			and String(refused.get("message", "")).contains("action.burn"),
		"%s %s" % [String(refused.get("code", "-")), String(refused.get("message", ""))],
	)


func _case_save_locale() -> void:
	_section("TC-SAVE-004 a resumed run reads in the locale of the interface")
	MemoryBackend.reset()
	var strings := {
		"action.farm": "Farm the fields",
		"action.burn": "Burn the stores",
		"rank.1": "Captain",
		"rank.4": "General",
		"failure.0": "The granaries are empty.",
		"resource.standing.0": "barely heeded",
		"resource.standing.2": "named across the land",
	}
	var entry: Dictionary = PackageLoader.new().import_bytes(
		_labels_package("resume-locale", strings), _context()
	)["entry"]
	var session := Session.create(entry, {"locale": "zh-CN"})
	session.start()
	var opening := session.view()
	session.act("farm")
	MemoryBackend.reset()
	var store := SaveStore.new()
	var written := store.write(entry, 1, session.snapshot(), "一")
	_check("TC-SAVE-004: the run saves", written["ok"], String(written["message"]))
	var payload: Dictionary = store.read(entry, 1)["payload"]

	var english := SaveStore.new().resume(entry, payload, {"locale": "en"})
	_check("TC-SAVE-004: an English resume rebuilds the run", english != null, "null session")
	if english != null:
		var view := english.view()
		_check(
			"TC-SAVE-004: the resumed run reads the translated scene",
			String(view.get("text", "")) == "Opening.",
			String(view.get("text", "")),
		)
		var labels := []
		for action in view.get("actions", []):
			labels.append(String(action.get("label", "")))
		_check(
			"TC-SAVE-004: the resumed menu reads the translated labels",
			labels.has("Farm the fields") and not labels.has("屯田"),
			str(labels),
		)
		_check(
			"TC-SAVE-004: the resumed rank follows the interface locale",
			String(view.get("rank", "")) == "Captain",
			String(view.get("rank", "")),
		)
		var standing_label := String(view.get("labels", {}).get("standing", ""))
		_check(
			"TC-SAVE-004: a labelled resource follows the interface locale",
			standing_label == "named across the land",
			standing_label,
		)

	var chinese := SaveStore.new().resume(entry, payload, {"locale": "zh-CN"})
	_check(
		"TC-SAVE-004: a Chinese resume keeps the package text",
		chinese != null and String(chinese.view().get("text", "")) == "开场。",
		"null session" if chinese == null else String(chinese.view().get("text", "")),
	)

	var bare := SaveStore.new().resume(entry, payload)
	_check(
		"TC-SAVE-004: a resume with no locale falls back to the package text",
		bare != null and String(bare.view().get("text", "")) == "开场。",
		"null session" if bare == null else String(bare.view().get("text", "")),
	)
	_check(
		"TC-SAVE-004: the opening view is still the declared one",
		String(opening.get("text", "")) != "",
		str(opening.get("text", "")),
	)


func _case_save_flush() -> void:
	_section("TC-SAVE-003 a save is durable before the scene moves on")
	MemoryBackend.reset()
	var entry: Dictionary = PackageLoader.new().import_bytes(_turn_package("flush"), _context())["entry"]
	var session := Session.create(entry)
	session.start()

	var state := {"calls": 0, "durable": false}
	var store := SaveStore.new()
	store.flush_request = func() -> void:
		pass
	store.flush_probe = func() -> bool:
		state["calls"] = int(state["calls"]) + 1
		return bool(state["durable"])
	var written := store.write(entry, 1, session.snapshot(), "flush")
	_check("TC-SAVE-003: the write still lands", bool(written["ok"]), str(written))
	_check(
		"TC-SAVE-003: a write reports itself as pending until the backend is durable",
		bool(written.get("pending", false)),
		str(written)
	)
	_check("TC-SAVE-003: the store is not settled while the backend says no", not store.settled())
	state["durable"] = true
	_check("TC-SAVE-003: the store settles once the backend says yes", store.settled())
	_check("TC-SAVE-003: the probe was asked at least twice", int(state["calls"]) >= 2, str(state["calls"]))

	var plain := SaveStore.new()
	var quick := plain.write(entry, 2, session.snapshot(), "plain")
	_check(
		"TC-SAVE-003: a backend with nothing to flush reports the slot as saved",
		bool(quick["ok"]) and not bool(quick.get("pending", true)) and plain.settled(),
		str(quick)
	)

	var shell := _shell()
	var bytes := _package("flush-ui", {"id": "flush-ui"}, [], [], {"nodes": [{"id": "n1", "text": "Flush.", "choices": []}]})
	var imported := shell.try_import(bytes)
	_check("TC-SAVE-003: the fixture pack opens", String(imported.get("node", "")) == "n1", str(imported))
	var gate := {"durable": false}
	shell.saves.flush_request = func() -> void:
		pass
	shell.saves.flush_probe = func() -> bool:
		return bool(gate["durable"])
	var click := shell.save_to(1)
	_check("TC-SAVE-003: the save screen says it is writing", shell._status.text == Locale.text("ui.saving"), shell._status.text)
	gate["durable"] = true
	shell.poll_saves()
	_check(
		"TC-SAVE-003: the save screen says it is saved once the backend agrees",
		shell._status.text == Locale.text("ui.saved_to") % 1,
		shell._status.text
	)
	_check("TC-SAVE-003: the save screen stays open after the write", String(shell.screen) == "saves" and click.has("node"), str(shell.screen))


func _case_pools() -> void:
	_section("TC-POOL-001 drawing from a pool")
	var nodes := {"nodes": [{"id": "n1", "text": "One.", "choices": []}]}
	var pools := {
		"pools": [
			{"id": "officers", "items": ["cao", "liu", "sun"], "draw": {"n": 1, "replace": false}},
			{"id": "loot", "items": ["axe", "bow"], "draw": {"n": 2, "replace": true}},
		],
	}
	var result: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"pool-draw",
			{"id": "pool-draw"},
			[],
			[],
			nodes,
			{},
			{"data/pools.json": JSON.stringify(pools).to_utf8_buffer()},
		),
		_context()
	)
	var entry: Dictionary = result.get("entry", {})
	_check("TC-POOL-001: a package with a pool installs", not entry.is_empty(), str(result))
	var session := Session.create(entry)
	session.start()
	var first := session.draw("officers")
	_check(
		"TC-POOL-001: a draw takes the declared number of items",
		(first["items"] as Array).size() == 1,
		str(first)
	)
	_check(
		"TC-POOL-001: drawing removes the item unless replace is true",
		(session.pools_left.get("officers", []) as Array).size() == 2,
		str(session.pools_left)
	)
	var twin := Session.create(entry)
	twin.start()
	var twin_draw := twin.draw("officers")
	_check(
		"TC-POOL-001: the same seed draws the same items in the same order",
		str(twin_draw["items"]) == str(first["items"]),
		"%s vs %s" % [str(first["items"]), str(twin_draw["items"])]
	)
	session.draw("loot")
	session.draw("loot")
	_check(
		"TC-POOL-001: a pool that replaces keeps its contents",
		(session.pools_left.get("loot", []) as Array).size() == 2,
		str(session.pools_left)
	)

	MemoryBackend.reset()
	var store := SaveStore.new()
	var saved := store.write(entry, 1, session.snapshot(), "缺")
	_check("TC-POOL-001: the run saves", saved["ok"], String(saved["message"]))
	var payload: Dictionary = store.read(entry, 1)["payload"]
	var resumed := SaveStore.new().resume(entry, payload)
	_check(
		"TC-POOL-001: a resumed run keeps what is left of its pool",
		resumed != null and (resumed.pools_left.get("officers", []) as Array).size() == 2,
		"" if resumed == null else str(resumed.pools_left)
	)

	var too_big := {
		"pools": [{"id": "big", "items": ["a"], "draw": {"n": 2, "replace": false}}],
	}
	var refused: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"pool-too-big",
			{"id": "pool-too-big"},
			[],
			[],
			nodes,
			{},
			{"data/pools.json": JSON.stringify(too_big).to_utf8_buffer()},
		),
		_context()
	)
	_check(
		"TC-POOL-001: drawing more than the pool holds without replace is refused with V-19",
		String(refused.get("code", "")) == "V-19"
			and String(refused.get("message", "")).contains("without replace"),
		"%s %s" % [String(refused.get("code", "-")), String(refused.get("message", ""))]
	)
	var twice := {"pools": [{"id": "dupes", "items": ["a", "a"], "draw": {"n": 1, "replace": false}}]}
	var dup_refused: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"pool-dupes",
			{"id": "pool-dupes"},
			[],
			[],
			nodes,
			{},
			{"data/pools.json": JSON.stringify(twice).to_utf8_buffer()},
		),
		_context()
	)
	_check(
		"TC-POOL-001: an item listed twice is refused with V-19",
		String(dup_refused.get("code", "")) == "V-19",
		"%s %s" % [String(dup_refused.get("code", "-")), String(dup_refused.get("message", ""))]
	)


func _case_relations() -> void:
	_section("TC-REL-001 directed relations")
	var nodes := {"nodes": [{"id": "n1", "text": "One.", "choices": []}]}
	var factions := {
		"thresholds": {"ally": 60, "hostile": -60},
		"entities": [
			{"id": "wei", "label": "魏", "relations": {"shu": -40, "wu": 70}},
			{"id": "shu", "label": "蜀", "relations": {"wei": -40}},
			{"id": "wu", "label": "吴", "relations": {"wei": 70}},
		],
	}
	var result: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"rel-map",
			{"id": "rel-map"},
			[],
			[],
			nodes,
			{},
			{"data/factions.json": JSON.stringify(factions).to_utf8_buffer()},
		),
		_context()
	)
	var entry: Dictionary = result.get("entry", {})
	_check("TC-REL-001: a package with a faction map installs", not entry.is_empty(), str(result))
	var session := Session.create(entry)
	session.start()
	_check(
		"TC-REL-001: a relation reads in the direction the package wrote",
		is_equal_approx(session.relation("wei", "shu"), -40.0)
			and is_equal_approx(session.relation("shu", "wei"), -40.0)
			and is_equal_approx(session.relation("wei", "wu"), 70.0),
		"%s %s %s" % [session.relation("wei", "shu"), session.relation("shu", "wei"), session.relation("wei", "wu")]
	)
	_check(
		"TC-REL-001: a state name comes from the package thresholds",
		session.relation_state("wei", "wu") == "ally"
			and session.relation_state("wei", "shu") == "",
		"%s %s" % [session.relation_state("wei", "wu"), session.relation_state("wei", "shu")]
	)
	_check(
		"TC-REL-001: the faction map lists the labels the package wrote",
		str(session.faction_map()).contains("魏") and str(session.faction_map()).contains("吴"),
		str(session.faction_map())
	)

	var lopsided := {
		"thresholds": {"ally": 60},
		"entities": [
			{"id": "wei", "relations": {"wu": 70}},
			{"id": "wu", "relations": {"wei": 10}},
		],
	}
	var warned: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"rel-lopsided",
			{"id": "rel-lopsided"},
			[],
			[],
			nodes,
			{},
			{"data/factions.json": JSON.stringify(lopsided).to_utf8_buffer()},
		),
		_context()
	)
	var warn_codes: Array = []
	for issue in warned.get("warnings", []):
		warn_codes.append(String(issue.get("code", "")))
	_check(
		"TC-REL-001: an asymmetric pair installs with a W-02 warning",
		not (warned.get("entry", {}) as Dictionary).is_empty() and warn_codes.has("W-02"),
		str(warn_codes)
	)

	var ghost := {
		"thresholds": {"ally": 60},
		"entities": [{"id": "wei", "relations": {"ghost": 5}}],
	}
	var refused: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"rel-ghost",
			{"id": "rel-ghost"},
			[],
			[],
			nodes,
			{},
			{"data/factions.json": JSON.stringify(ghost).to_utf8_buffer()},
		),
		_context()
	)
	_check(
		"TC-REL-001: an unknown entity id is refused with V-20",
		String(refused.get("code", "")) == "V-20"
			and String(refused.get("message", "")).contains("ghost"),
		"%s %s" % [String(refused.get("code", "-")), String(refused.get("message", ""))]
	)


func _case_turn() -> void:
	_section("TC-TURN-001 the menu, the phase machine and a check")
	var nodes := {
		"nodes": [
			{"id": "n1", "text": "One.", "choices": [{"label": "Go", "next": "n2"}]},
			{"id": "n2", "text": "Two.", "choices": []},
		],
	}
	var ledger := {"resources": [{"id": "grain", "init": 10, "min": 0, "max": 100}, {"id": "pop", "init": 0, "min": 0, "max": 100}, {"id": "prestige", "init": 4, "min": 0, "max": 100}]}
	var actions := {
		"actions": [
			{"id": "recruit", "label": "招兵", "costs": {"grain": {"add": -20}}, "requires": [{"key": "grain", "op": "gte", "value": 20}], "effects": [{"pop": {"add": 3}}], "limit": {"per_run": 1}},
			{"id": "drill", "label": "操练", "effects": [{"pop": {"add": 1}}]},
		],
	}
	var phases := {"turns": 3, "ranks": [{"at": 1, "title": "校尉"}, {"at": 2, "title": "将军"}], "fail": [{"when": {"key": "pop", "op": "gte", "value": 3}, "reason": "人满为患"}]}
	var checks := {"checks": [{"id": "battle", "roll": {"dice": 1, "sides": 100}, "target": 60, "bonus": {"key": "prestige", "scale": 0.5}}]}
	var files := {
		"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
		"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
		"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
		"data/checks.json": JSON.stringify(checks).to_utf8_buffer(),
	}
	var menu_result: Dictionary = PackageLoader.new().import_bytes(
		_package("turn-menu", {"id": "turn-menu"}, [], [], nodes, {}, files),
		_context()
	)
	var entry: Dictionary = menu_result.get("entry", {})
	_check("TC-TURN-001: the package with a menu installs", not entry.is_empty(), str(menu_result))
	var session := Session.create(entry)
	session.start()

	var menu := session.menu()
	var recruit: Dictionary = menu[0]
	_check(
		"TC-TURN-001: an action whose requirement fails is listed as unavailable",
		not recruit["enabled"] and String(recruit["reason"]).contains("grain"),
		str(recruit)
	)
	var before := session.state.duplicate(true)
	session.act("recruit")
	_check(
		"TC-TURN-001: an unavailable action writes nothing",
		float(session.state.get("grain", 0.0)) == float(before.get("grain", -1.0)) and float(session.state.get("pop", 9.0)) == 0.0,
		str(session.state)
	)
	var drilled := session.act("drill")
	_check(
		"TC-TURN-001: an available action applies its effects",
		float(drilled["state"].get("pop", 0.0)) == 1.0,
		str(drilled["state"])
	)
	session.act("drill")
	var limited := session.act("drill")
	_check(
		"TC-TURN-001: the third drill ends the run through the failure condition",
		bool(limited.get("finished", false)) and String(limited.get("failReason", "")) == "人满为患",
		"%s %s" % [str(limited.get("finished", false)), String(limited.get("failReason", ""))]
	)

	var ledger_two := {"resources": [{"id": "grain", "init": 25, "min": 0, "max": 100}, {"id": "pop", "init": 0, "min": 0, "max": 100}]}
	var spend := {"actions": [{"id": "spend", "label": "spend", "costs": {"grain": {"add": -20}}, "effects": [{"pop": {"add": 1}}], "limit": {"per_run": 1}}]}
	var run_phases := {"turns": 3, "ranks": [{"at": 1, "title": "校尉"}, {"at": 2, "title": "将军"}], "fail": []}
	var run_files := {
		"data/state.json": JSON.stringify(ledger_two).to_utf8_buffer(),
		"data/actions.json": JSON.stringify(spend).to_utf8_buffer(),
		"data/phases.json": JSON.stringify(run_phases).to_utf8_buffer(),
	}
	var run_result: Dictionary = PackageLoader.new().import_bytes(
		_package("turn-run", {"id": "turn-run"}, [], [], nodes, {}, run_files),
		_context()
	)
	var run: Dictionary = run_result.get("entry", {})
	var run_session := Session.create(run)
	run_session.start()
	var spent := run_session.act("spend")
	_check(
		"TC-TURN-001: costs and effects are applied in one step",
		float(spent["state"].get("grain", 0.0)) == 5.0 and float(spent["state"].get("pop", 0.0)) == 1.0,
		str(spent["state"])
	)
	_check(
		"TC-TURN-001: acting advances the turn",
		int(spent.get("turn", 0)) == 2,
		str(spent.get("turn", -1))
	)
	var twice := run_session.act("spend")
	_check(
		"TC-TURN-001: a per-run limit refuses the second use and writes nothing",
		float(twice["state"].get("grain", 0.0)) == 5.0 and float(twice["state"].get("pop", 0.0)) == 1.0,
		str(twice["state"])
	)
	_check(
		"TC-TURN-001: the rank follows the turn",
		String(spent.get("rank", "")) == "将军",
		String(spent.get("rank", ""))
	)

	var check_run := Session.create(entry)
	check_run.start()
	var rolled := check_run.resolve("battle")
	var stored: Dictionary = check_run.state.get("checks", {}).get("battle", {})
	_check(
		"TC-TURN-001: a check stores the numbers that decided it",
		bool(rolled["ok"]) and stored.get("total", -1) == int(rolled["roll"]) + int(rolled["bonus"]) and stored.get("target", 0) == 60,
		str(stored)
	)
	var again := Session.create(entry)
	again.start()
	var second := again.resolve("battle")
	_check(
		"TC-TURN-001: the same seed repeats the same roll",
		int(second["roll"]) == int(rolled["roll"]),
		"%s vs %s" % [str(second["roll"]), str(rolled["roll"])]
	)


func _case_clock() -> void:
	_section("TC-CLOCK-001 the engine counts time and a rule can read it")
	var nodes := {
		"nodes": [
			{"id": "c1", "text": "One.", "choices": [{"label": "Go", "next": "c2", "effects": []}]},
			{"id": "c2", "text": "Two.", "choices": []},
		],
	}
	var ledger := {
		"resources": [
			{"id": "grown", "label": "growth", "init": 0, "min": 0, "max": 99},
		],
	}
	var actions := {"actions": [{"id": "wait", "label": "Wait", "effects": [{"grown": {"add": 0}}]}]}
	# The rule names the tick, which is the engine's own count and never a
	# resource: that is what V-21 asks for when a package declares a clock.
	var per_turn := {"rules": [{"when": {"key": "tick", "op": "gte", "value": 2}, "set": {"grown": {"value": 7}}}]}

	var turn_result: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"clock-turn",
			{"id": "clock-turn", "entry": "c1", "clock": {"per": "turn"}},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(per_turn).to_utf8_buffer(),
			},
		),
		_context()
	)
	var turn_entry: Dictionary = turn_result.get("entry", {})
	_check(
		"TC-CLOCK-001: a package that declares a clock installs",
		not turn_entry.is_empty(),
		"%s %s" % [String(turn_result.get("code", "-")), String(turn_result.get("message", ""))]
	)

	var turn_run := Session.create(turn_entry)
	turn_run.start()
	_check("TC-CLOCK-001: the tick starts at zero", turn_run.tick == 0, str(turn_run.tick))
	turn_run.act("wait")
	_check("TC-CLOCK-001: one action advances the tick once", turn_run.tick == 1, str(turn_run.tick))
	_check(
		"TC-CLOCK-001: the rule has not fired before its number",
		float(turn_run.state.get("grown", -1.0)) == 0.0,
		str(turn_run.state)
	)
	turn_run.act("wait")
	_check("TC-CLOCK-001: a second action reaches the number", turn_run.tick == 2, str(turn_run.tick))
	_check(
		"TC-CLOCK-001: a rule that reads the tick fires when it reaches the number",
		float(turn_run.state.get("grown", -1.0)) == 7.0,
		str(turn_run.state)
	)

	var node_only := Session.create(turn_entry)
	node_only.start()
	node_only.choose(0)
	_check(
		"TC-CLOCK-001: a per-turn clock does not count a plain node advance",
		node_only.tick == 0,
		str(node_only.tick)
	)

	var node_entry: Dictionary = PackageLoader.new().import_bytes(
		_package(
			"clock-node",
			{"id": "clock-node", "entry": "c1", "clock": {"per": "node"}},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(per_turn).to_utf8_buffer(),
			},
		),
		_context()
	)["entry"]
	var node_run := Session.create(node_entry)
	node_run.start()
	node_run.choose(0)
	_check("TC-CLOCK-001: a per-node clock counts every node advance", node_run.tick == 2, str(node_run.tick))

	var saved := SaveStore.new()
	var written := saved.write(turn_entry, 1, turn_run.snapshot())
	var payload: Dictionary = saved.read(turn_entry, 1)
	var resumed := saved.resume(turn_entry, payload.get("payload", {}))
	_check(
		"TC-CLOCK-001: the tick survives a save and a resume",
		bool(written["ok"]) and bool(payload["ok"]) and resumed != null and resumed.tick == 2,
		"%s %s" % [str(written), str(resumed.tick if resumed != null else -1)]
	)

	var no_reader := {"rules": []}
	var refuses_reader := PackageLoader.new().import_bytes(
		_package(
			"clock-unread",
			{"id": "clock-unread", "entry": "c1", "clock": {"per": "turn"}},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(no_reader).to_utf8_buffer(),
			},
		),
		_context()
	)
	_check(
		"TC-CLOCK-001: a clock nobody reads is refused with V-21",
		String(refuses_reader.get("code", "")) == "V-21",
		"%s %s" % [String(refuses_reader.get("code", "-")), String(refuses_reader.get("message", ""))]
	)

	var writes_tick := {"rules": [{"when": {"key": "tick", "op": "gte", "value": 1}, "set": {"tick": {"value": 0}}}]}
	var refuses_write := PackageLoader.new().import_bytes(
		_package(
			"clock-write",
			{"id": "clock-write", "entry": "c1", "clock": {"per": "turn"}},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
				"data/rules.json": JSON.stringify(writes_tick).to_utf8_buffer(),
			},
		),
		_context()
	)
	_check(
		"TC-CLOCK-001: a rule that writes the tick is refused at install time",
		String(refuses_write.get("code", "")) == "V-14",
		"%s %s" % [String(refuses_write.get("code", "-")), String(refuses_write.get("message", ""))]
	)


func _case_scene() -> void:
	# The engine could hand a package actions, turns, ranks and dice long before
	# anything on screen showed them: only the assertions could see a menu. These
	# five lines are the contract for drawing it, and each one is a separate fact
	# so a regression names the part that broke.
	_section("TC-SCENE-001 the scene draws the menu a package declares")
	var nodes := {
		"nodes": [
			{"id": "s1", "text": "A hall with a long table.", "choices": []},
		],
	}
	var ledger := {
		"resources": [
			{"id": "grain", "init": 10, "min": 0, "max": 100},
			{"id": "pop", "init": 0, "min": 0, "max": 100},
		],
	}
	var actions := {
		"actions": [
			{
				"id": "feast",
				"label": "Hold a feast",
				"costs": {"grain": {"add": -20}},
				"requires": [{"key": "grain", "op": "gte", "value": 20}],
				"effects": [{"pop": {"add": 1}}],
			},
			{"id": "drill", "label": "Drill the guard", "effects": [{"pop": {"add": 1}}]},
		],
	}
	var phases := {
		"turns": 5,
		"ranks": [{"at": 1, "title": "Captain"}, {"at": 2, "title": "Colonel"}],
		"fail": [{"when": {"key": "pop", "op": "gte", "value": 3}, "reason": "Too many mouths to feed."}],
	}
	var built: PackedByteArray = _package(
		"scene-menu",
		{"id": "scene-menu", "entry": "s1"},
		[],
		[],
		nodes,
		{},
		{
			"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
			"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
			"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
		}
	)
	var shell := _shell()
	shell.try_import(built)
	_check("TC-SCENE-001: the package with a menu opens its scene", shell.screen_name() == "session", shell.screen_name())
	var labels := _button_labels(shell)
	_check(
		"TC-SCENE-001: every declared action is a button",
		labels.has("Drill the guard") and labels.any(func(label: String) -> bool: return label.begins_with("Hold a feast")),
		str(labels)
	)
	var feast := _button_pressed_text(shell, "Hold a feast")
	_check(
		"TC-SCENE-001: an action that cannot be taken is disabled and says why",
		feast != null and feast.disabled and feast.text.contains("grain"),
		"disabled=%s text=%s" % [feast.disabled if feast != null else "no button", feast.text if feast != null else "-"]
	)
	var before := int(shell.session.turn)
	shell.act("drill")
	var after := int(shell.session.turn)
	_check(
		"TC-SCENE-001: taking an action advances the turn and shows the rank",
		after == before + 1 and shell._status.text.contains("Colonel"),
		"turn %d to %d, status %s" % [before, after, shell._status.text]
	)
	shell.act("drill")
	shell.act("drill")
	_check(
		"TC-SCENE-001: an ended run shows why and offers no actions",
		shell._sub.text.contains("Too many mouths") and not _button_labels(shell).has("Drill the guard"),
		"%s %s" % [shell._sub.text, str(_button_labels(shell))]
	)

	var plain := _shell()
	plain.start_plugin("xiuxian")
	var plain_labels := _button_labels(plain)
	var turn_prefix := Locale.text("ui.turn_rank").get_slice("%d", 0)
	_check(
		"TC-SCENE-001: a package without actions looks exactly as before",
		not plain._status.text.contains(turn_prefix) and not plain_labels.has("屯田"),
		"%s %s" % [str(plain_labels), plain._status.text]
	)


func _art_package(name: String, variant: String = "") -> PackedByteArray:
	## A hand where one card carries a picture and one does not. The variants
	## build the two failures: a card naming a texture the manifest never
	## declares, and a declared texture whose bytes are not a picture.
	var cards := [
		{"id": "raid", "label": "Raid the stores", "icon": "assets/card-raid.png", "cost": {"coin": {"add": -1}}},
		{"id": "feast", "label": "Hold a feast", "cost": {"grain": {"add": -1}}},
	]
	if variant == "bad-icon":
		cards[0]["icon"] = "assets/card-ghost.png"
	var pictures := {"assets/card-raid.png": _png_bytes(8, 8)}
	if variant == "broken-icon":
		pictures = {"assets/card-raid.png": "this is not a picture".to_utf8_buffer()}
	var assets := [{"type": "texture", "path": "assets/card-raid.png", "slot": "card"}]
	var files := {
		"data/state.json": JSON.stringify({
			"resources": [
				{"id": "grain", "init": 10, "min": 0, "max": 20},
				{"id": "coin", "init": 5, "min": 0, "max": 10},
			],
		}).to_utf8_buffer(),
		"data/phases.json": JSON.stringify({"turns": 8, "ranks": [{"at": 1, "title": "Captain"}], "fail": []}).to_utf8_buffer(),
		"data/cards.json": JSON.stringify({"hand": {"size": 2, "draw_per_turn": 0}, "cards": cards, "deck": ["raid", "feast"]}).to_utf8_buffer(),
	}
	for picture_path in pictures:
		files[picture_path] = pictures[picture_path]
	return _package(
		name,
		{"id": name, "entry": "c1", "assets": assets, "capabilities": ["cards.hand@1", "ledger@1", "phases@1"], "mechanics": ["cards", "ledger", "phases"]},
		[],
		[],
		{"nodes": [{"id": "c1", "text": "A table with two cards on it.", "choices": []}]},
		{},
		files,
	)


func _case_card_art() -> void:
	# A card game where every card is a phrase is readable and forgettable. A
	# card may name a picture the package declares; the hand draws it beside the
	# label, and a card that names a picture nobody declared is refused at
	# install rather than losing its face silently (REQ-037).
	_section("TC-CARDS-002 a card shows the picture its package declares")
	var shell := _shell()
	shell.try_import(_art_package("art-run"))
	_check("TC-CARDS-002: a package with a card picture installs", shell.session != null, str(shell.notice))
	if shell.session == null:
		return
	var view: Dictionary = shell.session.view()
	var cards: Array = view.get("hand", [])
	_check(
		"TC-CARDS-002: the view reports the icon a card declares",
		cards.size() == 2 and String(cards[0].get("icon", "")) == "assets/card-raid.png",
		JSON.stringify(cards),
	)
	_check(
		"TC-CARDS-002: a card without an icon reports none",
		cards.size() == 2 and not cards[1].has("icon"),
		JSON.stringify(cards),
	)
	var rows: Array = shell.card_rows()
	_check("TC-CARDS-002: the scene builds one row per card", rows.size() == 2, str(rows.size()))
	if rows.size() == 2:
		_check("TC-CARDS-002: the row with an icon holds a picture", bool(rows[0].get("has_icon", false)), str(rows[0]))
		_check("TC-CARDS-002: the row without an icon holds none", not bool(rows[1].get("has_icon", false)), str(rows[1]))

	var broken := _shell()
	broken.try_import(_art_package("art-broken", "broken-icon"))
	_check(
		"TC-CARDS-002: a picture that does not decode keeps the label",
		broken.session != null and not (broken.session.view().get("hand", []) as Array).is_empty(),
		str(broken.notice),
	)
	if broken.session != null:
		var said := ""
		for warning in broken.session.warnings:
			said += String(warning.get("message", ""))
		_check("TC-CARDS-002: a broken picture leaves one warning", said.contains("card icon"), said)

	var bad := _shell()
	var refused: Dictionary = bad.try_import(_art_package("art-bad", "bad-icon"))
	_check(
		"TC-CARDS-002: a card naming an undeclared picture is refused at install",
		String(refused.get("code", "")) == "V-39",
		str(refused),
	)
	_check(
		"TC-CARDS-002: the refusal names the missing picture",
		String(refused.get("text", "")).contains("card-ghost.png"),
		String(refused.get("text", "")),
	)

	var duel := _shell()
	duel.start_plugin("duel")
	if duel.session != null:
		var icons := {}
		for entry in duel.session.hand_spec.get("cards", {}).values():
			if entry is Dictionary and entry.has("icon"):
				icons[String(entry["icon"])] = true
		_check("TC-CARDS-002: the shipped duel deck has one picture per card", icons.size() == 6, str(icons.keys()))


func _long_hand_package(name: String) -> PackedByteArray:
	## A hand deep enough to matter: eight cards with labels long enough that the
	## extra width has to come from somewhere. The short-hand case reuses
	## `_cards_package`, which holds two.
	var cards: Array = []
	var deck: Array = []
	for index in 8:
		cards.append({
			"id": "card-%d" % index,
			"label": "Order number %d, a long instruction the player has to read" % index,
			"cost": {"coin": {"add": -1}},
			"effects": [{"grain": {"add": 1}}],
		})
		deck.append("card-%d" % index)
	var files := {
		"data/state.json": JSON.stringify({
			"resources": [
				{"id": "grain", "init": 10, "min": 0, "max": 20},
				{"id": "coin", "init": 9, "min": 0, "max": 9},
			],
		}).to_utf8_buffer(),
		"data/phases.json": JSON.stringify({
			"turns": 12,
			"ranks": [{"at": 1, "title": "Captain"}],
			"fail": [],
		}).to_utf8_buffer(),
		"data/cards.json": JSON.stringify({
			"hand": {"size": 8, "draw_per_turn": 1, "reshuffle": true},
			"cards": cards,
			"deck": deck,
		}).to_utf8_buffer(),
	}
	return _package(
		name,
		{"id": name, "entry": "c1", "capabilities": ["cards.hand@1", "ledger@1", "phases@1"], "mechanics": ["cards", "ledger", "phases"]},
		[],
		[],
		{"nodes": [{"id": "c1", "text": "Eight orders wait on the table.", "choices": []}]},
		{},
		files,
	)


func _case_hand_layout() -> void:
	# B41 drew one card per line; B43 added a face to each. A deck of eight — the
	# duel deck is already eight — then carried the action buttons and the save
	# row off the bottom of a narrow window. The property asserted here is that
	# the hand wraps, and that wrapping is measured from the width rather than
	# declared as a constant.
	_section("TC-HAND-001 a long hand wraps into rows that stay inside the window")
	var shell := _shell()
	shell.set_layout_width(600.0)
	shell.try_import(_long_hand_package("long-hand-run"))
	if shell.session == null:
		_check("TC-HAND-001: the long-hand package installs", false, str(shell.notice))
		return
	_check("TC-HAND-001: all eight cards are in hand", (shell.card_rows() as Array).size() == 8, str(shell.card_rows().size()))
	var columns := shell.hand_columns()
	_check("TC-HAND-001: a 600 px window fits more than one card per row", columns >= 2, "%d column(s)" % columns)
	var rows := shell.hand_row_count()
	_check("TC-HAND-001: the hand takes more than one row", rows > 1, "%d row(s)" % rows)
	var drawn := 0
	var widest := 0.0
	for child in shell._hand_box.get_children():
		var row := child as HBoxContainer
		drawn += row.get_child_count()
		_check(
			"TC-HAND-001: a row holds no more cards than the window fits",
			row.get_child_count() <= columns,
			"%d card(s) in a row of %d columns" % [row.get_child_count(), columns]
		)
		widest = maxf(widest, row.get_combined_minimum_size().x)
	_check("TC-HAND-001: every card is laid out once", drawn == 8, "%d card(s) drawn" % drawn)
	_check("TC-HAND-001: a wrapped row fits the window", widest <= 600.0, "widest row asks %.1f px" % widest)
	# A wider window has to re-wrap the same cards into fewer rows; a constant
	# column count would pass the assertions above and fail this one.
	shell.set_layout_width(1200.0)
	_check(
		"TC-HAND-001: a wider window needs fewer rows",
		shell.hand_row_count() < rows,
		"%d row(s) at 1200 px, %d at 600 px" % [shell.hand_row_count(), rows]
	)
	# The action menu and the save row still follow the hand, one column like
	# before; the hand is the only thing that wrapped.
	var options := shell._options.get_children()
	_check(
		"TC-HAND-001: the menu still follows the hand",
		options.size() > 0 and options[options.size() - 1] is Button,
		"%d child(ren) after the hand" % options.size()
	)
	# A hand that fits on one row keeps its whole label: the clip is a
	# consequence of wrapping, not a property of cards.
	shell.set_layout_width(600.0)
	shell.try_import(_cards_package("short-hand-run"))
	if shell.session != null:
		_check("TC-HAND-001: a short hand stays on one row", shell.hand_row_count() == 1, "%d row(s)" % shell.hand_row_count())
		var first: Button = shell._cell_button(shell._hand_cells[0] as Control)
		_check(
			"TC-HAND-001: a short hand keeps the whole label",
			first != null and first.text == "Raid the stores",
			first.text if first != null else "no button"
		)



func _shuffle_package(name: String) -> PackedByteArray:
	## Six distinct cards, two in hand, one drawn a turn. Small enough that a run
	## empties the deck quickly, large enough that "the refill happens to equal
	## the play order" is not something a passing test can rely on.
	var cards: Array = []
	var deck: Array = []
	for index in 6:
		cards.append({
			"id": "c%d" % index,
			"label": "Card %d" % index,
			"cost": {},
			"effects": [],
		})
		deck.append("c%d" % index)
	var files := {
		"data/state.json": JSON.stringify({
			"resources": [{"id": "grain", "init": 5, "min": 0, "max": 20}],
		}).to_utf8_buffer(),
		"data/phases.json": JSON.stringify({
			"turns": 40,
			"ranks": [{"at": 1, "title": "Captain"}],
			"fail": [],
		}).to_utf8_buffer(),
		"data/cards.json": JSON.stringify({
			"hand": {"size": 2, "draw_per_turn": 1, "reshuffle": true},
			"cards": cards,
			"deck": deck,
		}).to_utf8_buffer(),
	}
	return _package(
		name,
		{"id": name, "entry": "c1", "capabilities": ["cards.hand@1", "ledger@1", "phases@1"], "mechanics": ["cards", "ledger", "phases"]},
		[],
		[],
		{"nodes": [{"id": "c1", "text": "A deck on the table.", "choices": []}]},
		{},
		files,
	)


func _play_turns(session: Session, count: int) -> void:
	for index in count:
		if session.hand.is_empty():
			return
		session.play_card(String(session.hand[0]))


func _case_shuffle() -> void:
	# The deck refilled in the order the cards were played, which let a player
	# learn eight cards by heart and made `reshuffle: true` mean "cycle". The
	# order now comes from the run's seeded generator, and the generator belongs
	# to the session: the hand stays a pure function of what it is handed.
	_section("TC-SHUFFLE-001 a deck is shuffled from the run's seed")
	var piles := {"hand": [], "deck": [], "discard": ["a", "b", "c"]}
	var plain: Dictionary = Hand.draw_into(piles, {"reshuffle": true}, 1)
	_check(
		"TC-SHUFFLE-001: a caller that gives no order still gets play order",
		str(plain.get("hand", [])) == '["a"]',
		str(plain.get("hand", [])),
	)
	var reversed: Dictionary = Hand.draw_into(piles, {"reshuffle": true}, 1, func(cards: Array) -> Array:
		var out := cards.duplicate()
		out.reverse()
		return out
	)
	_check(
		"TC-SHUFFLE-001: the order the caller passes is the order the deck takes",
		str(reversed.get("hand", [])) == '["c"]',
		str(reversed.get("hand", [])),
	)

	var shell := _shell()
	shell.try_import(_shuffle_package("shuffle-run"))
	if shell.session == null:
		_check("TC-SHUFFLE-001: the shuffle fixture installs", false, str(shell.notice))
		return
	var session: Session = shell.session
	_play_turns(session, 8)
	var everywhere := {}
	for card_id in session.hand + session.deck + session.discard:
		everywhere[String(card_id)] = int(everywhere.get(String(card_id), 0)) + 1
	_check("TC-SHUFFLE-001: the reshuffle keeps every card exactly once", everywhere.size() == 6, str(everywhere))
	# A reshuffle must not hand the discard pile back in the order it was played.
	var seeded := Session.create(shell.entry, {"start_counter": 7})
	var refill := Hand.draw_into(
		{"hand": [], "deck": [], "discard": ["c0", "c1", "c2", "c3", "c4", "c5"]},
		{"reshuffle": true},
		1,
		Callable(seeded, "_shuffle_cards"),
	)
	_check(
		"TC-SHUFFLE-001: the reshuffled deck is not the order the cards were played",
		str(refill["hand"]) != '["c0"]',
		str(refill["hand"]),
	)

	# The seed is the session's: one playthrough repeats, another does not.
	var first := Session.create(shell.entry, {"start_counter": 7})
	first.start()
	_play_turns(first, 20)
	var second := Session.create(shell.entry, {"start_counter": 7})
	second.start()
	_play_turns(second, 20)
	var other := Session.create(shell.entry, {"start_counter": 8})
	other.start()
	_play_turns(other, 20)
	_check(
		"TC-SHUFFLE-001: the same seed deals the same order",
		str(first.deck) == str(second.deck) and str(first.hand) == str(second.hand),
		"%s vs %s" % [str(first.deck), str(second.deck)],
	)
	_check(
		"TC-SHUFFLE-001: another seed deals another order",
		str(first.deck) != str(other.deck) or str(first.hand) != str(other.hand),
		"%s vs %s" % [str(first.deck), str(other.deck)],
	)

	# A save carries the order, so a resume must not shuffle again.
	var saves := SaveStore.new(MemoryBackend.new())
	saves.write(shell.entry, 1, first.snapshot(), "shuffled")
	var loaded: Dictionary = saves.read(shell.entry, 1)
	var resumed := saves.resume(shell.entry, loaded["payload"], {}) if bool(loaded.get("ok", false)) else null
	_check(
		"TC-SHUFFLE-001: the resume keeps the deck order the save carries",
		resumed != null and str(resumed.deck) == str(first.deck),
		"save %s, resume %s" % [str(first.deck), str(resumed.deck) if resumed != null else "none"],
	)


func _case_collection() -> void:
	# A repository is cut by world, and a world holds several packs. The screen
	# has to say so before the player picks a story; a single world keeps the
	# one-click path a repository with one theme has today (ADR-0012).
	_section("TC-COLLECTION-001 a package says which world it belongs to")
	var shell := _shell()
	shell.builtin_ids = ["sanguo", "jianghu"]
	_check(
		"TC-COLLECTION-001: packs that share a world offer one world",
		shell.worlds().size() == 2,
		str(shell.worlds()),
	)
	_check(
		"TC-COLLECTION-001: two worlds put the world screen between landing and packs",
		shell.start_game() == "worlds",
		shell.screen_name(),
	)
	Locale.set_current("en")
	_check(
		"TC-COLLECTION-001: a world title comes from the package that declares it",
		shell.world_title("three-kingdoms") == "Three Kingdoms",
		shell.world_title("three-kingdoms"),
	)
	Locale.set_current("zh-CN")
	_check(
		"TC-COLLECTION-001: a world title follows the interface locale",
		shell.world_title("three-kingdoms") == "三国",
		shell.world_title("three-kingdoms"),
	)
	Locale.set_current("en")

	var one := _shell()
	one.builtin_ids = ["sanguo"]
	_check(
		"TC-COLLECTION-001: one world skips the world screen",
		one.worlds().size() == 1 and one.start_game() == "plugins",
		"%d, %s" % [one.worlds().size(), one.screen_name()],
	)
	var none := _shell()
	none.builtin_ids = []
	_check(
		"TC-COLLECTION-001: a shell with no pack offers no world",
		none.worlds().is_empty() and none.start_game() == "plugins",
		"%d, %s" % [none.worlds().size(), none.screen_name()],
	)
	_check(
		"TC-COLLECTION-001: the fallback world is titled by the interface",
		none.world_title("") == "Other stories",
		none.world_title(""),
	)

	# Two packages that describe the same world differently are one world, and the
	# title is stable: the pack whose id sorts first supplies it.
	var first := _package("world-a", {
		"id": "world-a",
		"name": "World A",
		"collection": {"id": "three-kingdoms", "names": {"en": "Three Kingdoms", "zh-CN": "三国"}},
	})
	var second := _package("world-b", {
		"id": "world-b",
		"name": "World B",
		"collection": {"id": "three-kingdoms", "names": {"en": "The Three Kingdoms"}},
	})
	var loader := PackageLoader.new()
	var installed: Dictionary = loader.import_bytes(first, _context())
	var again: Dictionary = loader.import_bytes(second, _context())
	var w04 := 0
	for warning in again.get("warnings", []):
		if String(warning.get("code", "")) == "W-04":
			w04 += 1
	_check("TC-COLLECTION-001: the second package installs", again["status"] == "installed", str(again.get("code", "")))
	_check("TC-COLLECTION-001: two spellings leave one W-04", w04 == 1, str(again.get("warnings", [])))

	var off := _package("world-off", {
		"id": "world-c",
		"name": "World C",
		"collection": {"id": "Three Kingdoms", "names": {"en": "Three Kingdoms"}},
	})
	var refusal: Dictionary = loader.import_bytes(off, _context())
	_check(
		"TC-COLLECTION-001: an id that is not a slug is refused with V-32",
		String(refusal.get("code", "")) == "V-32",
		str(refusal.get("code", "")),
	)
	var empty := _package("world-empty", {
		"id": "world-d",
		"name": "World D",
		"collection": {"id": "three-kingdoms", "names": {}},
	})
	var blank: Dictionary = loader.import_bytes(empty, _context())
	_check(
		"TC-COLLECTION-001: a world without a title is refused with V-32",
		String(blank.get("code", "")) == "V-32",
		str(blank.get("code", "")),
	)


func _case_wire() -> void:
	# Two bricks could only be reached from the assertions: a relation had a value
	# nothing waited on, and a pool could only be drawn by calling the API. These
	# assertions are the contract for making both part of play.
	_section("TC-WIRE-001 a relation state and a drawn item can gate an action")
	var nodes := {"nodes": [{"id": "w1", "text": "A tent at dusk.", "choices": []}]}
	var ledger := {
		"resources": [
			{"id": "grain", "init": 10, "min": 0, "max": 100},
			{"id": "pop", "init": 0, "min": 0, "max": 100},
		],
	}
	var factions := {
		"thresholds": {"ally": 60, "hostile": -60},
		"entities": [
			{"id": "wei", "label": "Wei", "relations": {"shu": 70, "wu": -70}},
			{"id": "shu", "label": "Shu", "relations": {"wei": -40}},
			{"id": "wu", "label": "Wu", "relations": {"wei": -70}},
		],
	}
	var pools := {"pools": [{"id": "officers", "items": ["cao_cao"], "draw": {"n": 1, "replace": false}}]}
	var actions := {
		"actions": [
			{
				"id": "court",
				"label": "Court the house of Shu",
				"requires": [{"relation": "shu", "state": "ally"}],
				"effects": [{"pop": {"add": 1}}],
			},
			{
				"id": "betray",
				"label": "Turn on Wu",
				"requires": [{"relation": "wu", "state": "ally"}],
				"effects": [{"pop": {"add": 1}}],
			},
			{"id": "invite", "label": "Invite the general", "requires": [{"drawn": "cao_cao"}], "effects": [{"pop": {"add": 1}}]},
			{"id": "summon", "label": "Summon an officer", "draw": {"pool": "officers"}, "effects": [{"pop": {"add": 1}}]},
		],
	}
	var phases := {"turns": 10, "ranks": [], "fail": []}
	var files := {
		"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
		"data/factions.json": JSON.stringify(factions).to_utf8_buffer(),
		"data/pools.json": JSON.stringify(pools).to_utf8_buffer(),
		"data/actions.json": JSON.stringify(actions).to_utf8_buffer(),
		"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
	}
	var shell := _shell()
	shell.try_import(_package("wire-run", {"id": "wire-run", "entry": "w1"}, [], [], nodes, {}, files))
	_check("TC-WIRE-001: the package opens", shell.screen_name() == "session", "%s %s" % [shell.screen_name(), shell._sub.text])
	var court := _button_pressed_text(shell, "Court")
	var betray := _button_pressed_text(shell, "Turn on Wu")
	var invite := _button_pressed_text(shell, "Invite")
	_check(
		"TC-WIRE-001: an action waits on a relation state the package declared",
		court != null and not court.disabled,
		"disabled=%s text=%s" % [court.disabled if court != null else "no button", court.text if court != null else "-"]
	)
	_check(
		"TC-WIRE-001: a relation that is not in that state keeps the action disabled with a reason",
		betray != null and betray.disabled and betray.text.contains("wu"),
		"disabled=%s text=%s" % [betray.disabled if betray != null else "no button", betray.text if betray != null else "-"]
	)
	_check(
		"TC-WIRE-001: an action waits on an item that has not been drawn yet",
		invite != null and invite.disabled and invite.text.contains("cao_cao"),
		"disabled=%s text=%s" % [invite.disabled if invite != null else "no button", invite.text if invite != null else "-"]
	)
	var summon := _button_pressed_text(shell, "Summon")
	_check("TC-WIRE-001: the drawing action is available", summon != null and not summon.disabled)
	shell.act("summon")
	var drawn_ids: Array = []
	for entry in shell.session.drawn:
		drawn_ids.append(String(entry.get("item", "")))
	_check("TC-WIRE-001: the action drew from the pool in the same step", drawn_ids == ["cao_cao"], str(drawn_ids))
	_check(
		"TC-WIRE-001: the scene names what was drawn",
		shell._status.text.contains("cao_cao"),
		shell._status.text
	)
	var invite_after := _button_pressed_text(shell, "Invite")
	_check(
		"TC-WIRE-001: drawing the item unlocks the action that waits on it",
		invite_after != null and not invite_after.disabled,
		"disabled=%s text=%s" % [invite_after.disabled if invite_after != null else "no button", invite_after.text if invite_after != null else "-"]
	)
	shell.save_to(1)
	shell.load_from(1)
	var kept: Array = []
	for entry in shell.session.drawn:
		kept.append(String(entry.get("item", "")))
	_check(
		"TC-WIRE-001: the drawn items and the relation survive a resume",
		kept == ["cao_cao"] and shell.session.relation_state("wei", "shu") == "ally",
		"%s %s" % [str(kept), shell.session.relation_state("wei", "shu")]
	)

	var bad_state := {
		"actions": [
			{"id": "court", "label": "Court", "requires": [{"relation": "shu", "state": "legend"}], "effects": [{"pop": {"add": 1}}]},
		],
	}
	var state_bytes: PackedByteArray = _package(
		"wire-bad-state",
		{"id": "wire-bad-state", "entry": "w1"},
		[],
		[],
		nodes,
		{},
		{
			"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
			"data/factions.json": JSON.stringify(factions).to_utf8_buffer(),
			"data/actions.json": JSON.stringify(bad_state).to_utf8_buffer(),
			"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
		}
	)
	var refused_state: Dictionary = PackageLoader.new().import_bytes(state_bytes, _context())
	_check(
		"TC-WIRE-001: a relation state the package never declared is refused at install",
		String(refused_state.get("code", "")) == "V-25",
		"%s %s" % [String(refused_state.get("code", "-")), String(refused_state.get("message", ""))]
	)
	var bad_pool := {"actions": [{"id": "summon", "label": "Summon", "draw": {"pool": "ghosts"}, "effects": [{"pop": {"add": 1}}]}]}
	var pool_bytes: PackedByteArray = _package(
		"wire-bad-pool",
		{"id": "wire-bad-pool", "entry": "w1"},
		[],
		[],
		nodes,
		{},
		{
			"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
			"data/pools.json": JSON.stringify(pools).to_utf8_buffer(),
			"data/actions.json": JSON.stringify(bad_pool).to_utf8_buffer(),
			"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
		}
	)
	var refused_pool: Dictionary = PackageLoader.new().import_bytes(pool_bytes, _context())
	_check(
		"TC-WIRE-001: a draw naming a pool the package never declared is refused at install",
		String(refused_pool.get("code", "")) == "V-26",
		"%s %s" % [String(refused_pool.get("code", "-")), String(refused_pool.get("message", ""))]
	)


func _button_labels(shell: Shell) -> Array:
	var out: Array = []
	for child in shell._options.get_children():
		if child is Button:
			out.append(String((child as Button).text))
	return out


func _button_pressed_text(shell: Shell, prefix: String) -> Button:
	## The first button whose label starts with `prefix`, so a label that grows a
	## reason suffix is still findable.
	for child in shell._options.get_children():
		if child is Button and String((child as Button).text).begins_with(prefix):
			return child as Button
	return null


func _case_builtin_003() -> void:
	# A third story, written only as data, proves the bricks carry a whole new
	# kind of story: the ledger, the menu, the pool, the phase machine and the
	# English table, with the engine untouched.
	_section("TC-BUILTIN-003 Jianghu is played on the shipped bricks alone")
	var package := FileAccess.get_file_as_bytes(BUILTIN_JIANGHU)
	if package.is_empty():
		_failures.append("staged package missing at %s; run infra/stage_builtin.py" % BUILTIN_JIANGHU)
		return
	var loader := PackageLoader.new()
	var result := loader.import_bytes(package, _context())
	_check(
		"TC-BUILTIN-003: the package installs",
		result["status"] == "installed",
		"%s %s" % [String(result.get("code", "-")), String(result.get("message", ""))],
	)
	if result["status"] != "installed":
		return
	var shell := _shell()
	shell.start_plugin("jianghu")
	_check("TC-BUILTIN-003: the scene opens", shell.screen_name() == "session", shell.screen_name())
	var labels := _button_labels(shell)
	# Four actions plus Saves and Back to packs: the pack declares no choices.
	# The waiting action carries its reason inside the label, so match its prefix.
	var waiting := false
	for label in labels:
		if String(label).begins_with("Draw the old sword"):
			waiting = true
	_check(
		"TC-BUILTIN-003: the scene draws one button per declared action",
		labels.size() == 6 and labels.has("Search the back hill") and waiting,
		str(labels),
	)
	_check(
		"TC-BUILTIN-003: the first turn shows the first rank the package declared",
		shell._status.text.contains("new to the road"),
		shell._status.text,
	)
	var wield_before := _button_pressed_text(shell, "Draw the old sword")
	_check(
		"TC-BUILTIN-003: the action that waits on the item starts out unavailable",
		wield_before != null and wield_before.disabled,
		"disabled=%s" % str(wield_before.disabled if wield_before != null else "no button"),
	)
	shell.act("search")
	_check(
		"TC-BUILTIN-003: drawing from the pool tells the player what was found",
		shell._status.text.contains("old_sword"),
		shell._status.text,
	)
	var wield_after := _button_pressed_text(shell, "Draw the old sword")
	_check(
		"TC-BUILTIN-003: the drawn item unlocks the action that waits on it",
		wield_after != null and not wield_after.disabled,
		"disabled=%s" % str(wield_after.disabled if wield_after != null else "no button"),
	)
	var ended := {}
	for step in range(12):
		ended = shell.session.act("train")
		if bool(ended.get("finished", false)):
			break
	_check(
		"TC-BUILTIN-003: playing on ends the run with the failure reason the package declared",
		bool(ended.get("finished", false)) and String(ended.get("failReason", "")) == "You are spent and turn back.",
		"%s %s" % [str(ended.get("finished", false)), String(ended.get("failReason", ""))],
	)
	var english := Session.create(loader.registry.entry("jianghu"), {"start_counter": 1, "locale": "en"})
	var english_view := english.start()
	_check(
		"TC-BUILTIN-003: an English session reads the English table",
		String(english_view.get("text", "")).contains("last lamp in the inn"),
		String(english_view.get("text", "")),
	)


func _case_builtin_004() -> void:
	# A fourth story, and the first one played with cards: the hand, the deck
	# order, the discard pile and the refill all come from the package, and
	# nothing under app/core knows a card exists beyond the brick it declares.
	_section("TC-BUILTIN-004 Duel is played from a hand the package declares")
	var package := FileAccess.get_file_as_bytes(BUILTIN_DUEL)
	if package.is_empty():
		_failures.append("staged package missing at %s; run infra/stage_builtin.py" % BUILTIN_DUEL)
		return
	var loader := PackageLoader.new()
	var result := loader.import_bytes(package, _context())
	_check(
		"TC-BUILTIN-004: the package installs",
		result["status"] == "installed",
		"%s %s" % [String(result.get("code", "-")), String(result.get("message", ""))],
	)
	if result["status"] != "installed":
		return
	var shell := _shell()
	shell.start_plugin("duel")
	_check("TC-BUILTIN-004: the scene opens", shell.screen_name() == "session", shell.screen_name())
	var opening := _hand_ids(shell.session)
	_check(
		"TC-BUILTIN-004: the hand opens with the size the package declares, in its deck order",
		opening == ["heavy", "strike", "breathe", "feint"],
		str(opening),
	)
	shell.play_card("heavy")
	_check(
		"TC-BUILTIN-004: playing a card spends its cost and applies its effect in one step",
		int(shell.session.state.get("guard", -1)) == 8 and int(shell.session.state.get("edge", -1)) == 5,
		"guard=%s edge=%s" % [str(shell.session.state.get("guard")), str(shell.session.state.get("edge"))],
	)
	_check(
		"TC-BUILTIN-004: the played card is discarded and the hand is refilled",
		shell.session.discard.has("heavy") and _hand_ids(shell.session).size() == 4 and _hand_ids(shell.session).has("charge"),
		"discard=%s hand=%s" % [str(shell.session.discard), str(_hand_ids(shell.session))],
	)
	_check(
		"TC-BUILTIN-004: playing a card advances the turn",
		int(shell.session.turn) == 2,
		"turn=%s" % str(shell.session.turn),
	)
	var before := _hand_ids(shell.session)
	var refusals_before := shell.session.warnings.size()
	shell.play_card("charge")
	var said := ""
	for warning in shell.session.warnings.slice(refusals_before):
		said += String(warning.get("message", ""))
	_check(
		"TC-BUILTIN-004: a card whose cost the run cannot pay is refused by name",
		shell.session.warnings.size() > refusals_before and said.contains("edge"),
		said if said != "" else "no refusal recorded",
	)
	_check(
		"TC-BUILTIN-004: a refused card stays in the hand",
		_hand_ids(shell.session) == before,
		"%s vs %s" % [str(before), str(_hand_ids(shell.session))],
	)
	_check(
		"TC-BUILTIN-004: the rank is the package's word, not the engine's",
		shell._status.text.contains("untried"),
		shell._status.text,
	)
	var saved := shell.session.snapshot()
	var entry := loader.registry.entry("duel")
	var store := SaveStore.new()
	store.write(entry, 1, saved, "duel")
	var loaded := store.read(entry, 1)
	var resumed: Session = null
	if bool(loaded.get("ok", false)):
		resumed = store.resume(entry, loaded.get("payload", {}), {"locale": "en"})
	_check(
		"TC-BUILTIN-004: a save keeps the hand, the deck order and the discard pile",
		resumed != null and resumed.hand == shell.session.hand and resumed.deck == shell.session.deck and resumed.discard == shell.session.discard,
		"%s hand=%s deck=%s discard=%s" % [
			"no session" if resumed == null else "resumed",
			str(resumed.hand if resumed != null else []),
			str(resumed.deck if resumed != null else []),
			str(resumed.discard if resumed != null else []),
		],
	)


func _hand_ids(session: Session) -> Array:
	## The hand holds card ids, not card dictionaries: the deck is a list of ids
	## and `Hand.card()` looks the definition up in the package's table.
	var ids := []
	for card in session.hand:
		ids.append(String(card))
	return ids


func _case_capabilities() -> void:
	_section("TC-CAP-001 a package declares the engine capabilities it needs")
	var loader := PackageLoader.new()

	# A capability this engine provides installs. `ledger@1` is one of the
	# bricks, so asking for it must not depend on the package using the brick.
	var known := loader.import_bytes(
		_package("caps-known", {"capabilities": ["ledger@1", "text@1"]}),
		_context(),
	)
	_check("TC-CAP-001: a provided capability installs", known["status"] == "installed", String(known.get("code", "")))

	# A capability this engine does not provide is refused, and the refusal names
	# it: the contract is only usable if the failure says what is missing.
	var missing := loader.import_bytes(
		_package("caps-missing", {"capabilities": ["map@1"]}),
		_context(),
	)
	_check("TC-CAP-001: an unprovided capability is refused", missing["status"] == "rejected", String(missing.get("code", "")))
	_check(
		"TC-CAP-001: the refusal names the capability",
		String(missing.get("code", "")) == "V-27" and String(missing.get("message", "")).contains("map@1"),
		"%s / %s" % [missing.get("code", ""), missing.get("message", "")],
	)

	# Format 2.0.0 requires the versioned form. A bare name is a leftover of
	# 1.0.0 and is refused here rather than read as major zero.
	var unversioned := loader.import_bytes(
		_package("caps-unversioned", {"capabilities": ["text"]}),
		_context(),
	)
	_check(
		"TC-CAP-001: an unversioned id is refused in 2.0.0",
		String(unversioned.get("code", "")) == "V-27" and String(unversioned.get("message", "")).contains("text"),
		String(unversioned.get("message", "")),
	)

	# The same package written for 1.0.0 keeps installing, with one warning, so a
	# package published before this batch does not stop working (ADR-0006).
	var legacy := loader.import_bytes(
		_package("caps-legacy", {"id": "caps-legacy", "specVersion": "1.0.0", "capabilities": ["text"]}),
		_context(),
	)
	var w03 := 0
	for warning in legacy.get("warnings", []):
		if String(warning.get("code", "")) == "W-03":
			w03 += 1
	_check("TC-CAP-001: a 1.0.0 package still installs", legacy["status"] == "installed", String(legacy.get("code", "")))
	_check("TC-CAP-001: it carries one W-03 warning", w03 == 1, str(legacy.get("warnings", [])))

	# The ids the validator provides and the shape the schema parses cannot
	# drift: every known id has to read back as `name@major`.
	var known_ids := PackageValidator.known_capabilities()
	var broken: Array = []
	for capability in known_ids:
		if ManifestSchema.parse_capability(capability).is_empty():
			broken.append(capability)
	_check("TC-CAP-001: every known capability parses", broken.is_empty(), str(broken))
	_check("TC-CAP-001: the table covers the bricks", known_ids.size() >= 17, str(known_ids.size()))


func _assembly_package(name: String, variant: String = "") -> PackedByteArray:
	## Two files make one story: the base brings the ledger, the node and one
	## action; an addition brings its own resource and its own action. The
	## duplicate variant declares a key the base already has, so the placeholder
	## warning can be seen (merge semantics arrive in the next batch).
	var resources := [{"id": "grain", "init": 10, "min": 0, "max": 20}]
	var actions := [{"id": "farm", "label": "Farm", "effects": [{"grain": {"add": 2}}], "per_turn": 2}]
	if variant == "addon":
		resources = [{"id": "troops", "init": 3, "min": 0, "max": 9}]
		actions = [{"id": "drill", "label": "Drill", "effects": [{"troops": {"add": 1}}], "per_turn": 2}]
	if variant == "duplicate":
		resources = [{"id": "grain", "init": 1, "min": 0, "max": 99}]
		actions = []
	var files := {
		"data/state.json": JSON.stringify({"resources": resources}).to_utf8_buffer(),
		"data/actions.json": JSON.stringify({"actions": actions}).to_utf8_buffer(),
	}
	return _package(
		name,
		{"id": name, "entry": "camp", "capabilities": ["ledger@1"], "mechanics": ["ledger"]},
		[],
		[],
		{"nodes": [{"id": "camp", "text": "A camp.", "choices": []}]},
		{},
		files,
	)


func _case_assembly() -> void:
	# A story and the addition that changes it are two files, and a player who
	# installs both expects one run, not two. The session therefore has to be
	# opened from an ordered list and show one merged view (ADR-0013). This batch
	# stops at joining: a key two packages both declare is not resolved yet, it
	# keeps the earlier value and says so, because override and disable are the
	# next batch.
	_section("TC-ASSEMBLY-001 a run can be opened from more than one package")
	var loader := PackageLoader.new()
	var base: Dictionary = loader.import_bytes(_assembly_package("asm-base"), _context())
	var addon: Dictionary = loader.import_bytes(_assembly_package("asm-addon", "addon"), _context())
	_check(
		"TC-ASSEMBLY-001: both files of the assembly install",
		base["status"] == "installed" and addon["status"] == "installed",
		"%s / %s" % [base.get("code", ""), addon.get("code", "")],
	)
	var joined: Dictionary = loader.assemble(["asm-base", "asm-addon"])
	_check(
		"TC-ASSEMBLY-001: an assembly resolves to its packages in order",
		joined.get("ok", false) and (joined["entries"] as Array).size() == 2,
		str(joined.get("code", "")),
	)
	var entries: Array = joined.get("entries", [])
	if entries.size() != 2:
		return
	var session := Session.create(entries[0], {"assembly": entries.slice(1)})
	_check("TC-ASSEMBLY-001: a session opens from the assembly", session != null, "no session")
	if session == null:
		return
	session.start()
	var state: Dictionary = session.view()["state"]
	_check(
		"TC-ASSEMBLY-001: the readout shows the resources of both packages",
		state.has("grain") and state.has("troops"),
		str(state.keys()),
	)
	var ids: Array = []
	for item in session.menu():
		ids.append(String(item.get("id", "")))
	_check(
		"TC-ASSEMBLY-001: the menu carries the actions of both packages, in order",
		ids == ["farm", "drill"],
		str(ids),
	)
	_check(
		"TC-ASSEMBLY-001: the assembly is recorded in the save",
		session.snapshot().get("assembly", []) == ["asm-base", "asm-addon"],
		str(session.snapshot().get("assembly", [])),
	)
	MemoryBackend.reset()
	var store := SaveStore.new()
	store.write(entries[0], 1, session.snapshot(), "Assembly")
	var back: Dictionary = store.read(entries[0], 1)
	var resumed := store.resume(entries[0], back["payload"], {"assembly": entries.slice(1)})
	_check(
		"TC-ASSEMBLY-001: a resumed run rebuilds the same packages",
		resumed != null and resumed.view()["state"].has("troops"),
		"read %s %s; resumed %s; keys %s" % [back.get("code", ""), back.get("message", ""), str(resumed != null), str((resumed.view()["state"] as Dictionary).keys()) if resumed != null else "none"],
	)

	var missing: Dictionary = loader.assemble(["asm-base", "asm-ghost"])
	_check(
		"TC-ASSEMBLY-001: a package the assembly names but nothing installed is refused",
		not missing.get("ok", true) and String(missing.get("code", "")) == "V-33" and String(missing.get("message", "")).contains("asm-ghost"),
		"%s %s" % [missing.get("code", ""), missing.get("message", "")],
	)
	loader.import_bytes(_assembly_package("asm-dupe", "duplicate"), _context())
	var duped: Dictionary = loader.assemble(["asm-base", "asm-dupe"])
	var dupe_entries: Array = duped.get("entries", [])
	if dupe_entries.size() == 2:
		var dupe_session := Session.create(dupe_entries[0], {"assembly": dupe_entries.slice(1)})
		var codes: Array = []
		for warning in dupe_session.view()["warnings"]:
			codes.append(String(warning.get("code", "")))
		_check(
			"TC-ASSEMBLY-001: a key two packages both declare keeps the first and leaves one W-05",
			codes.count("W-05") == 1 and float(dupe_session.view()["state"]["grain"]) == 10.0,
			str(codes),
		)


func _layer_package(name: String, ignore: String = "") -> PackedByteArray:
	## A layer names the package it sits on, not the other way round, so the only
	## thing that makes it a layer is the target the assembly carries (REQ-042).
	## It replaces one resource definition, adds one action and removes one.
	var ledger := {
		"resources": [{"id": "grain", "init": 10.0, "min": 0.0, "max": 99.0, "label": "粮"}],
	}
	var actions := {
		"actions": [{"id": "drill", "label": "Drill", "per_turn": 1, "effects": [{"grain": {"add": 1}}]}],
	}
	var disable := {"actions": ["farm"]}
	return _package(
		name,
		{"id": name, "capabilities": ["ledger@1"], "mechanics": ["ledger"]},
		[],
		[],
		{},
		{},
		{
			"data/state.json": JSON.stringify(ledger, "\t").to_utf8_buffer(),
			"data/actions.json": JSON.stringify(actions, "\t").to_utf8_buffer(),
			"data/disable.json": JSON.stringify(disable, "\t").to_utf8_buffer(),
		},
	)


func _base_package(name: String) -> PackedByteArray:
	var ledger := {
		"resources": [{"id": "grain", "init": 10.0, "min": 0.0, "max": 20.0, "label": "粮"}],
	}
	var actions := {
		"actions": [{"id": "farm", "label": "Farm", "per_turn": 1, "effects": [{"grain": {"add": 5}}]}],
	}
	return _package(
		name,
		{"id": name, "capabilities": ["ledger@1"], "mechanics": ["ledger"]},
		[],
		[],
		{},
		{},
		{
			"data/state.json": JSON.stringify(ledger, "\t").to_utf8_buffer(),
			"data/actions.json": JSON.stringify(actions, "\t").to_utf8_buffer(),
		},
	)


func _case_layers() -> void:
	## TC-WIRE-002: a layer package changes the package it names. The three
	## semantics are the whole contract: override a definition, append new
	## entries, disable names. Everything else — a layer on a package that is not
	## in the assembly, a layer on itself, two layers pointing at each other — is
	## refused before a run opens.
	var loader := PackageLoader.new()
	var context := {"engine_version": "4.7.2", "work_dir": FIXTURE_DIR}
	var base: Dictionary = loader.import_bytes(_base_package("lay-base"), context)
	var layer: Dictionary = loader.import_bytes(_layer_package("lay-mod"), context)
	_check("TC-WIRE-002: a base and its layer install", base["status"] == "installed" and layer["status"] == "installed", "%s %s" % [base.get("code", ""), layer.get("code", "")])

	var resolved: Dictionary = loader.assemble([{"id": "lay-base"}, {"id": "lay-mod", "target": "lay-base"}])
	var entries: Array = resolved.get("entries", [])
	_check(
		"TC-WIRE-002: an assembly entry may name the package it sits on",
		resolved.get("ok", false) and entries.size() == 2 and String((entries[1] as Dictionary).get("target", "")) == "lay-base",
		"%s %s" % [resolved.get("code", ""), resolved.get("message", "")],
	)
	if not resolved.get("ok", false):
		return
	var layered := Session.create(entries[0], {"assembly": entries.slice(1)})
	var lay_state: Dictionary = layered.view()["state"]
	_check("TC-WIRE-002: a layer overrides a definition it declares", float(lay_state.get("grain", 0.0)) == 10.0 and float(layered.ledger_defs["grain"]["max"]) == 99.0, "%s %s" % [str(lay_state), str(layered.ledger_defs)])
	var lay_ids: Array = []
	for action in layered.actions:
		lay_ids.append(String(action.get("id", "")))
	_check("TC-WIRE-002: a layer appends an action and disables one", lay_ids == ["drill"], str(lay_ids))
	_check("TC-WIRE-002: the assembly records the layer in order", (layered.snapshot().get("assembly", []) as Array) == ["lay-base", "lay-mod"], str(layered.snapshot().get("assembly", [])))

	var alone := Session.create(entries[0], {})
	var alone_ids: Array = []
	for action in alone.actions:
		alone_ids.append(String(action.get("id", "")))
	_check(
		"TC-WIRE-002: without the layer the base is untouched",
		alone_ids == ["farm"] and float(alone.ledger_defs["grain"]["max"]) == 20.0,
		"%s %s" % [str(alone_ids), str(alone.ledger_defs)],
	)

	var stranger: Dictionary = loader.assemble([{"id": "lay-base"}, {"id": "lay-mod", "target": "nobody"}])
	_check(
		"TC-WIRE-002: a layer on a package the assembly does not name is refused",
		not stranger.get("ok", true) and String(stranger.get("code", "")) == "V-34" and String(stranger.get("message", "")).contains("nobody"),
		"%s %s" % [stranger.get("code", ""), stranger.get("message", "")],
	)
	var itself: Dictionary = loader.assemble([{"id": "lay-mod", "target": "lay-mod"}])
	_check(
		"TC-WIRE-002: a layer on itself is refused",
		not itself.get("ok", true) and String(itself.get("code", "")) == "V-34",
		"%s %s" % [itself.get("code", ""), itself.get("message", "")],
	)
	var ring: Dictionary = loader.import_bytes(_layer_package("lay-ring"), context)
	_check("TC-WIRE-002: a second layer installs", ring["status"] == "installed", str(ring.get("code", "")))
	var cycling: Dictionary = loader.assemble([
		{"id": "lay-mod", "target": "lay-ring"},
		{"id": "lay-ring", "target": "lay-mod"},
	])
	_check(
		"TC-WIRE-002: two layers pointing at each other are refused",
		not cycling.get("ok", true) and String(cycling.get("code", "")) == "V-34" and String(cycling.get("message", "")).contains("returns to"),
		"%s %s" % [cycling.get("code", ""), cycling.get("message", "")],
	)
	var twice: Dictionary = loader.assemble(["lay-base", "lay-base"])
	_check(
		"TC-WIRE-002: a package named twice is refused",
		not twice.get("ok", true) and String(twice.get("code", "")) == "V-34",
		"%s %s" % [twice.get("code", ""), twice.get("message", "")],
	)


func _layer_with_target(name: String, target: String, ledger: bool = true, action: bool = true, action_id: String = "drill") -> PackedByteArray:
	## A layer that names its own base (REQ-043). `target` empty means the package
	## forgot to say, which is the case the assembly has to refuse.
	var overrides := {"id": name, "kind": "layer", "layer": "mod", "capabilities": ["ledger@1"], "mechanics": ["ledger"]}
	if target != "":
		overrides["target"] = target
	var files := {}
	if ledger:
		files["data/state.json"] = JSON.stringify({
			"resources": [{"id": "grain", "init": 10.0, "min": 0.0, "max": 99.0, "label": "粮"}],
		}, "\t").to_utf8_buffer()
	if action:
		files["data/actions.json"] = JSON.stringify({
			"actions": [{"id": action_id, "label": "Drill", "per_turn": 1, "effects": [{"grain": {"add": 1}}]}],
		}, "\t").to_utf8_buffer()
	return _package(name, overrides, [], [], {}, {}, files)


func _content_package(name: String, content: Dictionary) -> PackedByteArray:
	## A story that declares how it reads (REQ-044). The phase machine gives it a
	## turn, so the arc has something to resolve against.
	var overrides := {
		"id": name,
		"capabilities": ["ledger@1", "phases@1"],
		"mechanics": ["ledger", "phases"],
		"content": content,
	}
	var files := {
		"data/state.json": JSON.stringify({
			"resources": [{"id": "grain", "init": 10.0, "min": 0.0, "max": 20.0, "label": "粮"}],
		}, "\t").to_utf8_buffer(),
		"data/actions.json": JSON.stringify({
			"actions": [{"id": "farm", "label": "Farm", "per_turn": 9, "effects": [{"grain": {"add": 1}}]}],
		}, "\t").to_utf8_buffer(),
		"data/phases.json": JSON.stringify({
			"turns": 9,
			"ranks": [{"at": 1, "title": "novice"}],
		}, "\t").to_utf8_buffer(),
	}
	return _package(name, overrides, [], [], {}, {}, files)


func _meta_package(name: String, meta: Dictionary, with_icon: bool = true) -> PackedByteArray:
	## A story that says who it is for (REQ-045). The icon, when asked for, is a
	## real 1x1 picture the manifest declares, so the V-42 texture check has
	## something true to look at.
	var overrides := {"id": name}
	if not meta.is_empty():
		overrides["meta"] = meta
	if with_icon:
		overrides["assets"] = [{"type": "texture", "path": "assets/pack.png", "slot": "scene"}]
	var pictures := {}
	if with_icon:
		pictures["assets/pack.png"] = _png_bytes(1, 1)
	return _package(name, overrides, [], [], {}, {}, pictures)


func _shipped_meta(plugin_id: String) -> Dictionary:
	## Reads the meta block of a package as it ships, without a browser: the same
	## loader the scene uses, pointed at the built-in zip.
	var loader := PackageLoader.new()
	var result := loader.import_bytes(
		FileAccess.get_file_as_bytes("res://builtin/%s.zip" % plugin_id),
		{"engine_version": "4.7.2", "work_dir": FIXTURE_DIR},
	)
	if String(result.get("status", "")) != "installed":
		return {}
	return MetaLayer.of(loader.registry.entry(plugin_id)["manifest"])


func _case_meta() -> void:
	## TC-META-001: the package says who it is for. The list shows the pitch and
	## the length, the pitch follows the reader's language with a documented
	## fallback, and a block the engine cannot honour is refused at install
	## (REQ-045).
	var loader := PackageLoader.new()
	var context := {"engine_version": "4.7.2", "work_dir": FIXTURE_DIR}
	var plain: Dictionary = loader.import_bytes(_meta_package("meta-plain", {}), context)
	var declared: Dictionary = loader.import_bytes(
		_meta_package("meta-declared", {
			"pitch": {"en": "A duel in two turns.", "zh-CN": "两回合的决斗。"},
			"audience": "teens",
			"minutes": 12,
			"icon": "assets/pack.png",
		}),
		context,
	)
	_check(
		"TC-META-001: a package with and without a meta block both install",
		String(plain.get("status", "")) == "installed" and String(declared.get("status", "")) == "installed",
		"%s %s" % [plain.get("code", ""), declared.get("code", "")],
	)
	if String(declared.get("status", "")) != "installed":
		return

	var plain_meta := MetaLayer.of(loader.registry.entry("meta-plain")["manifest"])
	_check(
		"TC-META-001: a package that declares nothing carries an empty meta",
		plain_meta.is_empty() and not MetaLayer.declared(loader.registry.entry("meta-plain")["manifest"]),
		str(plain_meta),
	)

	var entry := loader.registry.entry("meta-declared")
	var meta := MetaLayer.of(entry["manifest"])
	_check(
		"TC-META-001: the declared meta carries a pitch, an audience, a length and an icon",
		String(MetaLayer.pitch(meta, "en")) == "A duel in two turns."
			and String(meta.get("audience", "")) == "teens"
			and int(meta.get("minutes", 0)) == 12
			and String(meta.get("icon", "")) == "assets/pack.png",
		str(meta),
	)
	_check(
		"TC-META-001: the pitch follows the reader and falls back without going blank",
		String(MetaLayer.pitch(meta, "zh-CN")) == "两回合的决斗。"
			and String(MetaLayer.pitch(meta, "de")) == "A duel in two turns.",
		"%s %s" % [MetaLayer.pitch(meta, "zh-CN"), MetaLayer.pitch(meta, "de")],
	)

	var row := Shell.pack_line(meta, "en")
	_check(
		"TC-META-001: the pack list shows the pitch and the length",
		row.contains("A duel in two turns.") and row.contains("12"),
		row,
	)

	var bad_audience: Dictionary = loader.import_bytes(
		_meta_package("meta-bad-audience", {"audience": "everyone", "minutes": 5}),
		context,
	)
	var bad_minutes: Dictionary = loader.import_bytes(
		_meta_package("meta-bad-minutes", {"audience": "adults", "minutes": 0}),
		context,
	)
	var bad_pitch: Dictionary = loader.import_bytes(
		_meta_package("meta-bad-pitch", {"pitch": {"en": ""}, "minutes": 5}),
		context,
	)
	var bad_icon: Dictionary = loader.import_bytes(
		_meta_package("meta-bad-icon", {"minutes": 5, "icon": "assets/ghost.png"}),
		context,
	)
	var audience_issues := JSON.stringify(bad_audience.get("issues", []))
	var minutes_issues := JSON.stringify(bad_minutes.get("issues", []))
	var pitch_issues := JSON.stringify(bad_pitch.get("issues", []))
	var icon_issues := JSON.stringify(bad_icon.get("issues", []))
	_check(
		"TC-META-001: an audience, a length, a pitch and an icon the engine cannot honour are refused with V-42",
		String(bad_audience.get("status", "")) == "rejected" and audience_issues.contains("V-42")
			and String(bad_minutes.get("status", "")) == "rejected" and minutes_issues.contains("V-42")
			and String(bad_pitch.get("status", "")) == "rejected" and pitch_issues.contains("V-42")
			and String(bad_icon.get("status", "")) == "rejected" and icon_issues.contains("V-42"),
		"%s %s %s %s" % [audience_issues, minutes_issues, pitch_issues, icon_issues],
	)
	_check(
		"TC-META-001: the refusal names the field it is about",
		audience_issues.contains("audience") and minutes_issues.contains("minutes")
			and pitch_issues.contains("pitch") and icon_issues.contains("icon"),
		"%s %s %s %s" % [audience_issues, minutes_issues, pitch_issues, icon_issues],
	)

	for plugin_id in ["sanguo", "xiuxian", "jianghu"]:
		var shipped_meta := _shipped_meta(plugin_id)
		_check(
			"TC-META-001: %s declares a pitch in both languages and a length" % plugin_id,
			MetaLayer.pitch(shipped_meta, "en") != "" and MetaLayer.pitch(shipped_meta, "zh-CN") != ""
				and int(shipped_meta.get("minutes", 0)) > 0,
			str(shipped_meta),
		)


func _case_content() -> void:
	## TC-CONTENT-001: the package says how its story reads. The engine honours a
	## view, a density, a cast and an arc it knows, refuses the ones it does not,
	## and carries the declaration through a save (REQ-044).
	var loader := PackageLoader.new()
	var context := {"engine_version": "4.7.2", "work_dir": FIXTURE_DIR}
	var plain: Dictionary = loader.import_bytes(_content_package("con-plain", {}), context)
	var third: Dictionary = loader.import_bytes(
		_content_package("con-third", {
			"view": "third",
			"density": "normal",
			"cast": [{"id": "guan", "name": "Guan", "role": "captain"}],
			"arc": [{"turn": 1, "label": "opening"}, {"turn": 3, "label": "middle"}],
		}),
		context,
	)
	_check(
		"TC-CONTENT-001: a package with and without a declaration both install",
		String(plain.get("status", "")) == "installed" and String(third.get("status", "")) == "installed",
		"%s %s" % [plain.get("code", ""), third.get("code", "")],
	)
	if String(third.get("status", "")) != "installed":
		return

	var quiet := Session.create(loader.registry.entry("con-plain"), {})
	_check(
		"TC-CONTENT-001: a package that declares nothing keeps the old view",
		not quiet.view().has("content"),
		str(quiet.view().keys()),
	)

	var declared := Session.create(loader.registry.entry("con-third"), {})
	var view := declared.view()
	var block: Dictionary = view.get("content", {})
	_check(
		"TC-CONTENT-001: the declared view, density, cast and stage reach the view",
		String(block.get("view", "")) == "third"
			and String(block.get("density", "")) == "normal"
			and String(block.get("cast", "")).contains("Guan (captain)")
			and String(block.get("cast_names", "")) == "Guan"
			and String(block.get("stage", "")) == "opening",
		str(block),
	)

	var shell := _shell()
	var sparse := declared.view()
	sparse["content"] = (sparse["content"] as Dictionary).duplicate(true)
	sparse["content"]["density"] = "sparse"
	sparse["situation"] = {"turnsLeft": 4}
	_check(
		"TC-CONTENT-001: the sparse density hides the situation line",
		not shell._readout(sparse).contains("turns left"),
		shell._readout(sparse),
	)
	var dense := declared.view()
	dense["content"] = (dense["content"] as Dictionary).duplicate(true)
	dense["content"]["density"] = "dense"
	_check(
		"TC-CONTENT-001: the dense density names the stage and its turn",
		shell._readout(dense).contains("arc: opening (from turn 1)"),
		shell._readout(dense),
	)

	var before := ContentLayer.arc_at(ContentLayer.defines({
		"arc": [{"turn": 3, "label": "middle"}],
	}), 2)
	var after := ContentLayer.arc_at(ContentLayer.defines({
		"arc": [{"turn": 3, "label": "middle"}],
	}), 5)
	_check(
		"TC-CONTENT-001: the arc says nothing before its first stage and holds the last one",
		before.is_empty() and String(after.get("label", "")) == "middle",
		"%s %s" % [str(before), str(after)],
	)

	var bad_view: Dictionary = loader.import_bytes(
		_content_package("con-bad-view", {"view": "second"}),
		context,
	)
	var bad_density: Dictionary = loader.import_bytes(
		_content_package("con-bad-density", {"density": "dense-ish"}),
		context,
	)
	var view_issues := JSON.stringify(bad_view.get("issues", []))
	var density_issues := JSON.stringify(bad_density.get("issues", []))
	_check(
		"TC-CONTENT-001: a view or a density the engine does not know is refused with V-40",
		String(bad_view.get("status", "")) == "rejected" and view_issues.contains("V-40")
			and String(bad_density.get("status", "")) == "rejected" and density_issues.contains("V-40"),
		"%s %s" % [view_issues, density_issues],
	)

	var bad_cast: Dictionary = loader.import_bytes(
		_content_package("con-bad-cast", {
			"cast": [{"id": "guan", "name": "Guan"}, {"id": "guan", "name": "Guan again"}],
		}),
		context,
	)
	var bad_arc: Dictionary = loader.import_bytes(
		_content_package("con-bad-arc", {
			"arc": [{"turn": 5, "label": "late"}, {"turn": 3, "label": "early"}],
		}),
		context,
	)
	var cast_issues := JSON.stringify(bad_cast.get("issues", []))
	var arc_issues := JSON.stringify(bad_arc.get("issues", []))
	_check(
		"TC-CONTENT-001: a repeated cast id and a falling arc are refused with V-41",
		String(bad_cast.get("status", "")) == "rejected" and cast_issues.contains("V-41")
			and String(bad_arc.get("status", "")) == "rejected" and arc_issues.contains("V-41"),
		"%s %s" % [cast_issues, arc_issues],
	)

	MemoryBackend.reset()
	var store := SaveStore.new(MemoryBackend.new())
	declared.start()
	declared.act("farm")
	var payload := declared.snapshot()
	var saved := store.write(loader.registry.entry("con-third"), 1, payload, "con-third")
	_check("TC-CONTENT-001: the declared story saves", String(saved.get("code", "")) == "", str(saved.get("code", "")))
	var loaded := store.read(loader.registry.entry("con-third"), 1)
	var resumed := store.resume(loader.registry.entry("con-third"), loaded.get("payload", {}), {"locale": "en"})
	_check(
		"TC-CONTENT-001: the declaration comes back with the resumed run",
		resumed != null and String((resumed.view().get("content", {}) as Dictionary).get("view", "")) == "third",
		str(resumed.view().get("content", {})) if resumed != null else "null",
	)


func _case_wire3() -> void:
	## TC-WIRE-003: the target belongs to the package. A layer names its base in
	## the manifest, the assembly may override it, a layer with no target anywhere
	## is refused, and two layers writing the same field are refused with a code
	## that names both.
	var loader := PackageLoader.new()
	var context := {"engine_version": "4.7.2", "work_dir": FIXTURE_DIR}
	var base: Dictionary = loader.import_bytes(_base_package("w3-base"), context)
	var other_base: Dictionary = loader.import_bytes(_base_package("w3-other"), context)
	var layer: Dictionary = loader.import_bytes(_layer_with_target("w3-mod", "w3-base"), context)
	var orphan: Dictionary = loader.import_bytes(_layer_with_target("w3-orphan", ""), context)
	var twin: Dictionary = loader.import_bytes(_layer_with_target("w3-twin", "w3-base"), context)
	var neighbour: Dictionary = loader.import_bytes(_layer_with_target("w3-neighbour", "w3-base", false, true, "scout"), context)
	var bundle: Dictionary = loader.import_bytes(
		_package("w3-bundle", {"id": "w3-bundle", "target": "w3-base"}, [], [], {}, {}, {}),
		context,
	)
	_check(
		"TC-WIRE-003: a base and a layer install, and a layer that forgot its target does not",
		base["status"] == "installed" and layer["status"] == "installed"
			and orphan["status"] == "rejected" and String(orphan.get("code", "")) == "V-23",
		"%s %s %s" % [base.get("code", ""), layer.get("code", ""), orphan.get("code", "")],
	)
	_check(
		"TC-WIRE-003: the manifest carries the target the package declared",
		String((loader.registry.entry("w3-mod")["manifest"] as Dictionary).get("target", "")) == "w3-base",
		str((loader.registry.entry("w3-mod")["manifest"] as Dictionary).get("target", "none")),
	)

	var declared: Dictionary = loader.assemble(["w3-base", "w3-mod"])
	var declared_entries: Array = declared.get("entries", [])
	var layered := Session.create(declared_entries[0], {"assembly": declared_entries.slice(1)}) if declared.get("ok", false) else null
	_check(
		"TC-WIRE-003: an assembly may name only the package and let the manifest decide",
		declared.get("ok", false) and declared_entries.size() == 2
			and String((declared_entries[1] as Dictionary).get("target", "")) == "w3-base"
			and layered != null and float(layered.ledger_defs["grain"]["max"]) == 99.0,
		"%s %s" % [declared.get("code", ""), declared.get("message", "")],
	)

	var stray: Dictionary = loader.assemble(["w3-base", "w3-orphan"])
	_check(
		"TC-WIRE-003: a layer that never installed cannot be named by an assembly",
		not stray.get("ok", true) and String(stray.get("code", "")) == "V-33",
		"%s %s" % [stray.get("code", ""), stray.get("message", "")],
	)

	_check(
		"TC-WIRE-003: a bundle that declares a target is refused as a manifest problem",
		bundle["status"] == "rejected" and String(bundle.get("code", "")) == "V-23",
		"%s %s" % [bundle.get("status", ""), str(bundle.get("issues", bundle.get("code", "")))],
	)

	var override: Dictionary = loader.assemble(["w3-other", {"id": "w3-mod", "target": "w3-other"}])
	var override_entries: Array = override.get("entries", [])
	var rebuilt := Session.create(override_entries[0], {"assembly": override_entries.slice(1)}) if override.get("ok", false) else null
	_check(
		"TC-WIRE-003: an assembly target wins over the manifest target",
		override.get("ok", false) and rebuilt != null and float(rebuilt.ledger_defs["grain"]["max"]) == 99.0,
		"%s %s" % [override.get("code", ""), override.get("message", "")],
	)

	var clash: Dictionary = loader.assemble(["w3-base", "w3-mod", "w3-twin"])
	var clash_message := String(clash.get("message", ""))
	_check(
		"TC-WIRE-003: two layers writing the same field are refused and both are named",
		not clash.get("ok", true) and String(clash.get("code", "")) == "V-35" and clash_message.contains("w3-mod") and clash_message.contains("w3-twin"),
		"%s %s" % [clash.get("code", ""), clash_message],
	)

	var apart: Dictionary = loader.assemble(["w3-base", "w3-mod", "w3-neighbour"])
	_check(
		"TC-WIRE-003: two layers writing different fields both apply",
		apart.get("ok", false),
		"%s %s" % [apart.get("code", ""), apart.get("message", "")],
	)

	if layered != null:
		MemoryBackend.reset()
		var store := SaveStore.new()
		layered.start()
		store.write(declared_entries[0], 1, layered.snapshot(), "Layered")
		var back: Dictionary = store.read(declared_entries[0], 1)
		var resumed := store.resume(declared_entries[0], back["payload"], {"assembly": declared_entries.slice(1)})
		var ids: Array = []
		if resumed != null:
			for action in resumed.actions:
				ids.append(String(action.get("id", "")))
		_check(
			"TC-WIRE-003: a saved layered run comes back with the same assembly",
			resumed != null and (resumed.snapshot().get("assembly", []) as Array) == ["w3-base", "w3-mod"] and ids == ["farm", "drill"],
			"%s %s" % [str(ids), str(resumed.snapshot().get("assembly", [])) if resumed != null else "none"],
		)


func _cards_package(name: String, variant: String = "") -> PackedByteArray:
	## A run whose options are held in a hand instead of a menu: two cards in
	## hand, one drawn per turn, and a deck that repeats. The variants build the
	## refusals: a deck naming a card that does not exist, a cost key the ledger
	## never declared, and a package that claims the capability but brings no hand.
	var hand := {"size": 2, "draw_per_turn": 1, "reshuffle": true}
	var cards := [
		{"id": "raid", "label": "Raid the stores", "cost": {"coin": {"add": -3}}, "effects": [{"grain": {"add": 4}}]},
		{"id": "feast", "label": "Hold a feast", "cost": {"grain": {"add": -1}}, "effects": [{"coin": {"add": 2}}]},
	]
	var deck := ["raid", "feast", "raid"]
	if variant == "bad-deck":
		deck = ["raid", "ghost"]
	if variant == "bad-cost":
		cards[0]["cost"] = {"silver": {"add": -3}}
	var files := {
		"data/state.json": JSON.stringify({
			"resources": [
				{"id": "grain", "init": 10, "min": 0, "max": 20},
				{"id": "coin", "init": 5, "min": 0, "max": 10},
			],
		}).to_utf8_buffer(),
		"data/phases.json": JSON.stringify({
			"turns": 8,
			"ranks": [{"at": 1, "title": "Captain"}],
			"fail": [],
		}).to_utf8_buffer(),
		"data/cards.json": JSON.stringify({"hand": hand, "cards": cards, "deck": deck}).to_utf8_buffer(),
	}
	if variant == "no-hand":
		files["data/cards.json"] = JSON.stringify({"cards": cards, "deck": deck}).to_utf8_buffer()
	return _package(
		name,
		{"id": name, "entry": "c1", "capabilities": ["cards.hand@1", "ledger@1", "phases@1"], "mechanics": ["cards", "ledger", "phases"]},
		[],
		[],
		{"nodes": [{"id": "c1", "text": "A hall before the council.", "choices": []}]},
		{},
		files,
	)


func _case_cards() -> void:
	# A hand is not a differently drawn menu: it is state that has to be held,
	# paid for, refilled and carried through a save. The menu could not hold an
	# option that disappears when used, so a card battle had nothing to stand on.
	_section("TC-CARDS-001 a package declares a deck and a hand, and the save keeps them")
	var shell := _shell()
	var installed := shell.try_import(_cards_package("cards-run"))
	_check("TC-CARDS-001: a package with a hand installs", shell.session != null, str(installed.get("code", "")))
	if shell.session == null:
		return
	var session: Session = shell.session
	var opening: Dictionary = session.view()
	_check(
		"TC-CARDS-001: the hand opens at its declared size",
		(session.hand as Array).size() == 2,
		str(session.hand),
	)
	_check(
		"TC-CARDS-001: the hand holds the front of the deck in order",
		str(session.hand) == '["raid", "feast"]',
		str(session.hand),
	)
	_check(
		"TC-CARDS-001: the view offers the hand as cards",
		(opening.get("hand", []) as Array).size() == 2,
		str(opening.get("hand", [])),
	)
	# Playing a card is one turn: it pays, it lands, and the clock moves.
	session.play_card("raid")
	_check(
		"TC-CARDS-001: playing a card pays its cost",
		float(session.state.get("coin", -1.0)) == 2.0,
		str(session.state.get("coin", "absent")),
	)
	_check(
		"TC-CARDS-001: playing a card applies its effects in the same step",
		float(session.state.get("grain", -1.0)) == 14.0,
		str(session.state.get("grain", "absent")),
	)
	_check(
		"TC-CARDS-001: the played card leaves the hand and reaches the discard pile",
		not (session.hand as Array).has("raid") or (session.discard as Array).has("raid"),
		"hand %s · discard %s" % [session.hand, session.discard],
	)
	_check(
		"TC-CARDS-001: the hand refills by the declared draw per turn",
		(session.hand as Array).size() == 2 and (session.discard as Array).has("raid"),
		"hand %s · discard %s" % [session.hand, session.discard],
	)
	_check("TC-CARDS-001: the turn advanced", session.turn == 2, str(session.turn))
	# A card the run cannot pay for stays put, and the refusal names the resource.
	var before_hand: Array = (session.hand as Array).duplicate()
	session.play_card("raid")
	var refusals: Array = []
	for warning in session.warnings:
		if String(warning.get("code", "")) == "S-08":
			refusals.append(warning)
	_check("TC-CARDS-001: an unaffordable card is refused", refusals.size() == 1, str(refusals))
	_check(
		"TC-CARDS-001: the refusal names the resource that is short",
		refusals.size() == 1 and String(refusals[0].get("message", "")).contains("coin"),
		str(refusals),
	)
	_check(
		"TC-CARDS-001: an unaffordable card stays in the hand",
		str(session.hand) == str(before_hand),
		"%s vs %s" % [session.hand, before_hand],
	)
	# The hand, the deck order and the discard pile are part of the save.
	var payload: Dictionary = session.snapshot()
	_check(
		"TC-CARDS-001: the payload carries the hand, the deck and the discard pile",
		payload.has("hand") and payload.has("deck") and payload.has("discard"),
		str(payload.keys()),
	)
	var store := SaveStore.new()
	var written := store.write(shell.entry, 1, payload, "Cards")
	var read_back := store.read(shell.entry, 1)
	var resumed: Session = null
	if bool(written.get("ok", false)) and bool(read_back.get("ok", false)):
		resumed = store.resume(shell.entry, read_back["payload"])
	_check(
		"TC-CARDS-001: the hand, the deck and the discard pile survive a resume",
		resumed != null and str(resumed.hand) == str(payload["hand"]) and str(resumed.deck) == str(payload["deck"]) and str(resumed.discard) == str(payload["discard"]),
		"" if resumed == null else "hand %s · deck %s · discard %s" % [resumed.hand, resumed.deck, resumed.discard],
	)

	# Three refusals, each naming what is wrong rather than saying "bad package".
	var loader := PackageLoader.new()
	var ghost := loader.import_bytes(_cards_package("cards-ghost", "bad-deck"), _context())
	_check(
		"TC-CARDS-001: a deck naming a card that does not exist is refused",
		ghost["status"] == "rejected" and String(ghost.get("code", "")) == "V-38",
		"%s %s" % [ghost.get("code", ""), ghost.get("message", "")],
	)
	_check(
		"TC-CARDS-001: the refusal names the missing card",
		String(ghost.get("message", "")).contains("ghost"),
		String(ghost.get("message", "")),
	)
	var silver := loader.import_bytes(_cards_package("cards-silver", "bad-cost"), _context())
	_check(
		"TC-CARDS-001: a cost key the ledger never declared is refused",
		silver["status"] == "rejected" and String(silver.get("code", "")) == "V-37",
		"%s %s" % [silver.get("code", ""), silver.get("message", "")],
	)
	var bare := loader.import_bytes(_cards_package("cards-bare", "no-hand"), _context())
	_check(
		"TC-CARDS-001: claiming the capability without a hand is refused",
		bare["status"] == "rejected" and String(bare.get("code", "")) == "V-36",
		"%s %s" % [bare.get("code", ""), bare.get("message", "")],
	)


func _long_wav_bytes(seconds: float) -> PackedByteArray:
	## A canonical 44-byte WAV header followed by silence at 8 kHz mono 8-bit, so
	## `PackageLimits.wav_seconds()` reports the requested duration without the
	## fixture having to be a real recording.
	var bytes := PackedByteArray()
	bytes.append_array("RIFF".to_utf8_buffer())
	bytes.append_array([0, 0, 0, 0])
	bytes.append_array("WAVEfmt ".to_utf8_buffer())
	bytes.append_array([16, 0, 0, 0, 1, 0, 1, 0])
	bytes.append_array([0x40, 0x1F, 0, 0])
	bytes.append_array([0x40, 0x1F, 0, 0])
	bytes.append_array([1, 0, 8, 0])
	bytes.append_array("data".to_utf8_buffer())
	bytes.append_array([0, 0, 0, 0])
	var silence := PackedByteArray()
	silence.resize(int(8000.0 * seconds))
	bytes.append_array(silence)
	return bytes


func _case_writable_relations() -> void:
	# A relation could be read but never moved: rules wrote resources only, so a
	# story could not earn an alliance it did not declare up front. These
	# assertions are the contract for making the write path part of play.
	_section("TC-REL-002 a rule can move a relation, and a save keeps it")
	MemoryBackend.reset()
	var nodes := {"nodes": [{"id": "r1", "text": "The envoys wait.", "choices": []}]}
	var ledger := {
		"resources": [
			{"id": "grain", "init": 10, "min": 0, "max": 100},
			{"id": "pop", "init": 0, "min": 0, "max": 100},
		],
	}
	var factions := {
		"thresholds": {"ally": 60, "hostile": -60},
		"entities": [
			{"id": "wei", "label": "Wei", "relations": {"shu": 70}},
			{"id": "shu", "label": "Shu", "relations": {"wei": -40}},
		],
	}
	var rules := {
		"rules": [
			{
				"when": {"key": "grain", "op": "gte", "value": 5},
				"set": {"grain": {"add": -1}, "pop": {"add": 1}},
				"relations": [{"from": "wei", "to": "shu", "add": -20}],
			},
		],
	}
	var phases := {"turns": 10, "ranks": [], "fail": []}
	var files := {
		"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
		"data/factions.json": JSON.stringify(factions).to_utf8_buffer(),
		"data/rules.json": JSON.stringify(rules).to_utf8_buffer(),
		"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
	}
	var loader := PackageLoader.new()
	var entry: Dictionary = loader.import_bytes(
		_package("relation-run", {"id": "relation-run", "entry": "r1"}, [], [], nodes, {}, files),
		_context(),
	)["entry"]
	var session := Session.create(entry)
	_check(
		"TC-REL-002: the component keeps the state it declared until a rule runs",
		session.relation_state("wei", "shu") == "ally",
		"%s %.1f" % [session.relation_state("wei", "shu"), session.relation("wei", "shu")],
	)
	session.start()
	_check(
		"TC-REL-002: a rule moves the relation it names",
		session.relation("wei", "shu") == 50.0,
		"%.1f" % session.relation("wei", "shu"),
	)
	_check(
		"TC-REL-002: the moved relation leaves the state it was in",
		session.relation_state("wei", "shu") == "",
		session.relation_state("wei", "shu"),
	)
	_check(
		"TC-REL-002: the opposite direction is untouched",
		session.relation("shu", "wei") == -40.0,
		"%.1f" % session.relation("shu", "wei"),
	)

	var store := SaveStore.new()
	store.write(entry, 1, session.snapshot())
	var read := store.read(entry, 1)
	var resumed := store.resume(entry, read["payload"])
	_check(
		"TC-REL-002: the moved relation survives a save and a resume",
		resumed != null and resumed.relation("wei", "shu") == 50.0,
		"null" if resumed == null else "%.1f" % resumed.relation("wei", "shu"),
	)

	var quiet: Dictionary = loader.import_bytes(
		_package(
			"relation-quiet",
			{"id": "relation-quiet", "entry": "r1"},
			[],
			[],
			nodes,
			{},
			{
				"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
				"data/factions.json": JSON.stringify(factions).to_utf8_buffer(),
				"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
			},
		),
		_context(),
	)["entry"]
	var quiet_session := Session.create(quiet)
	quiet_session.start()
	_check(
		"TC-REL-002: a package that writes no relation behaves as before",
		quiet_session.relation_state("wei", "shu") == "ally",
		quiet_session.relation_state("wei", "shu"),
	)

	# V-31: the write has to name entities the package declared, and it has to be
	# a number. Both are refused before the session ever runs.
	var bad_target := files.duplicate(true)
	bad_target["data/rules.json"] = JSON.stringify({
		"rules": [{"set": {"pop": {"add": 1}}, "relations": [{"from": "wei", "to": "nobody", "add": 5}]}],
	}).to_utf8_buffer()
	var refused: Dictionary = loader.import_bytes(
		_package("relation-bad-target", {"id": "relation-bad-target", "entry": "r1"}, [], [], nodes, {}, bad_target),
		_context(),
	)
	_check(
		"TC-REL-002: a write naming an undeclared entity is refused at install",
		refused["status"] == "rejected" and String(refused.get("code", "")) == "V-31",
		"%s / %s" % [refused.get("code", ""), refused.get("message", "")],
	)

	var bad_source := files.duplicate(true)
	bad_source["data/rules.json"] = JSON.stringify({
		"rules": [{"set": {"pop": {"add": 1}}, "relations": [{"from": "nobody", "to": "shu", "add": 5}]}],
	}).to_utf8_buffer()
	var refused_source: Dictionary = loader.import_bytes(
		_package("relation-bad-source", {"id": "relation-bad-source", "entry": "r1"}, [], [], nodes, {}, bad_source),
		_context(),
	)
	_check(
		"TC-REL-002: a write that starts from an undeclared entity is refused too",
		refused_source["status"] == "rejected" and String(refused_source.get("code", "")) == "V-31",
		"%s / %s" % [refused_source.get("code", ""), refused_source.get("message", "")],
	)

	var bad_change := files.duplicate(true)
	bad_change["data/rules.json"] = JSON.stringify({
		"rules": [{"set": {"pop": {"add": 1}}, "relations": [{"from": "wei", "to": "shu", "add": "lots"}]}],
	}).to_utf8_buffer()
	var refused_change: Dictionary = loader.import_bytes(
		_package("relation-bad-change", {"id": "relation-bad-change", "entry": "r1"}, [], [], nodes, {}, bad_change),
		_context(),
	)
	_check(
		"TC-REL-002: a write whose change is not a number is refused at install",
		refused_change["status"] == "rejected" and String(refused_change.get("code", "")) == "V-31",
		"%s / %s" % [refused_change.get("code", ""), refused_change.get("message", "")],
	)


func _case_situation() -> void:
	# The player has to weigh three things every turn: the time left, who stands
	# with them, and which number is about to run out. The engine knew all three
	# and said none of them. These assertions are the contract for saying it once,
	# in one place, from what the package declared.
	_section("TC-SITUATION-001 the scene states how the run stands")
	var nodes := {"nodes": [{"id": "t1", "text": "A hall before dawn.", "choices": []}]}
	var ledger := {
		"resources": [
			{"id": "grain", "init": 3, "min": 0, "max": 10},
			{"id": "coin", "init": 60, "min": 0, "max": 100},
		],
	}
	var factions := {
		"thresholds": {"ally": 60, "hostile": -60},
		"entities": [
			{"id": "wei", "label": "Wei", "relations": {"shu": -10}},
			{"id": "shu", "label": "Shu", "relations": {"wei": 70}},
			{"id": "wu", "label": "Wu", "relations": {"wei": 20, "shu": -40}},
		],
	}
	var phases := {"turns": 6, "ranks": [{"at": 1, "title": "Captain"}], "fail": []}
	var built: PackedByteArray = _package(
		"situation-run",
		{"id": "situation-run", "entry": "t1"},
		[],
		[],
		nodes,
		{},
		{
			"data/state.json": JSON.stringify(ledger).to_utf8_buffer(),
			"data/factions.json": JSON.stringify(factions).to_utf8_buffer(),
			"data/phases.json": JSON.stringify(phases).to_utf8_buffer(),
		}
	)
	var shell := _shell()
	shell.try_import(built)
	var view: Dictionary = shell.session.view()
	var situation: Dictionary = view.get("situation", {})
	_check(
		"TC-SITUATION-001: the view carries a situation section",
		not situation.is_empty(),
		str(situation),
	)
	_check(
		"TC-SITUATION-001: turnsLeft counts down from the declared turn budget",
		int(situation.get("turnsLeft", -1)) == 6,
		str(situation.get("turnsLeft", "absent")),
	)
	_check(
		"TC-SITUATION-001: leaning is the entity others lean toward",
		String(situation.get("leaning", "")) == "wei",
		str(situation.get("leaning", "absent")),
	)
	_check(
		"TC-SITUATION-001: friction is the entity others push against",
		String(situation.get("friction", "")) == "shu",
		str(situation.get("friction", "absent")),
	)
	_check(
		"TC-SITUATION-001: tight is the resource closest to its floor",
		String(situation.get("tight", "")) == "grain",
		str(situation.get("tight", "absent")),
	)
	_check(
		"TC-SITUATION-001: the scene says it in one line",
		shell._status.text.contains("Wei") and shell._status.text.contains("Shu") and shell._status.text.contains("6"),
		shell._status.text,
	)
	# The line has to come from the catalog: switching the language switches it.
	shell.toggle_language()
	_check(
		"TC-SITUATION-001: the line follows the interface language",
		shell._status.text.contains("最受拥护") and shell._status.text.contains("最紧"),
		shell._status.text,
	)
	shell.toggle_language()
	# A run that is over reports no time left rather than a negative count.
	shell.session.turn = 9
	var late: Dictionary = shell.session.view().get("situation", {})
	_check(
		"TC-SITUATION-001: turnsLeft never goes below zero",
		int(late.get("turnsLeft", -1)) == 0,
		str(late.get("turnsLeft", "absent")),
	)
	# A package that declares neither faction nor phases gets no invented sections.
	var bare: PackedByteArray = _package(
		"situation-bare",
		{"id": "situation-bare", "entry": "t1"},
		[],
		[],
		nodes,
		{},
		{"data/state.json": JSON.stringify(ledger).to_utf8_buffer()}
	)
	var bare_shell := _shell()
	bare_shell.try_import(bare)
	var bare_situation: Dictionary = bare_shell.session.view().get("situation", {})
	_check(
		"TC-SITUATION-001: a section whose source is undeclared is left out",
		bare_situation.is_empty(),
		str(bare_situation),
	)
	_check(
		"TC-SITUATION-001: a story with no run state reads as it did before",
		not bare_shell._status.text.contains("turnsLeft"),
		bare_shell._status.text,
	)


func _case_limits() -> void:
	_section("TC-SAFE-001 a package is held to the install-time envelope")
	var loader := PackageLoader.new()

	# Entry count. The archive is small but holds more files than a plugin may.
	var many: Array = []
	for index in 501:
		many.append("data/part-%03d.json" % index)
	var crowded := loader.import_bytes(_package("limits-many", {}, [], many), _context())
	_check("TC-SAFE-001: too many entries is refused", String(crowded.get("code", "")) == "V-28", String(crowded.get("code", "")))
	_check("TC-SAFE-001: the count is reported", String(crowded.get("message", "")).contains("the limit is 500"), String(crowded.get("message", "")))

	# Path shape. A path that climbs out of the package, or one a filesystem would
	# treat differently, is refused before any content is read.
	var climbing := loader.import_bytes(_package("limits-climb", {}, [], ["../evil.json"]), _context())
	_check("TC-SAFE-001: a path that climbs out is refused", String(climbing.get("code", "")) == "V-29", String(climbing.get("code", "")))
	var uppercase := loader.import_bytes(_package("limits-case", {}, [], ["Data/Extra.json"]), _context())
	_check("TC-SAFE-001: an uppercase path is refused", String(uppercase.get("code", "")) == "V-29", String(uppercase.get("code", "")))

	# One entry that unpacks past the per-entry cap.
	var fat := PackedByteArray()
	fat.resize(5 * 1024 * 1024)
	var heavy := loader.import_bytes(
		_package("limits-heavy", {}, [], [], {}, {}, {"data/big.bin": fat}),
		_context(),
	)
	_check("TC-SAFE-001: an oversized entry is refused", String(heavy.get("code", "")) == "V-28", String(heavy.get("code", "")))
	_check("TC-SAFE-001: the entry is named", String(heavy.get("message", "")).contains("data/big.bin"), String(heavy.get("message", "")))

	# Asset limits: a picture past 4096 px and audio past 60 seconds.
	var wide := loader.import_bytes(
		_package(
			"limits-wide",
			{"assets": [{"type": "texture", "path": "assets/huge.png"}]},
			[],
			[],
			{},
			{},
			{"assets/huge.png": _png_bytes(5000, 5000)},
		),
		_context(),
	)
	_check("TC-SAFE-001: an oversized picture is refused", String(wide.get("code", "")) == "V-30", String(wide.get("code", "")))
	_check("TC-SAFE-001: the picture size is reported", String(wide.get("message", "")).contains("5000"), String(wide.get("message", "")))

	var long_audio := loader.import_bytes(
		_package(
			"limits-long",
			{"assets": [{"type": "audio", "path": "assets/long.wav"}]},
			[],
			[],
			{},
			{},
			{"assets/long.wav": _long_wav_bytes(90.0)},
		),
		_context(),
	)
	_check("TC-SAFE-001: audio past a minute is refused", String(long_audio.get("code", "")) == "V-30", String(long_audio.get("code", "")))
	_check("TC-SAFE-001: the duration is reported", String(long_audio.get("message", "")).contains("90.0"), String(long_audio.get("message", "")))

	# The two limits no fixture can reach without building a genuinely large
	# archive are exercised through the helpers the loader itself calls.
	_check("TC-SAFE-001: an oversized archive is refused", PackageLimits.archive_problem(9 * 1024 * 1024).contains("9.0 MB"))
	_check("TC-SAFE-001: an oversized total is refused", PackageLimits.total_problem(40 * 1024 * 1024).contains("40.0 MB"))

	# A package inside the envelope still installs: the limits must refuse nothing
	# the three built-in packages do.
	var fits := loader.import_bytes(
		_package(
			"limits-fits",
			{"assets": [{"type": "texture", "path": "assets/ok.png"}]},
			[],
			["data/extra.json"],
			{},
			{},
			{"assets/ok.png": _png_bytes(100, 100)},
		),
		_context(),
	)
	_check("TC-SAFE-001: a package inside the envelope installs", fits["status"] == "installed", String(fits.get("code", "")))


func _case_boot() -> void:
	# B31. The shell reads the size and the cache answer from the page; these
	# assertions feed that state in and check the sentence the player reads.
	_section("TC-BOOT-001 the first visit names the download and a refused cache")
	var shell := _shell()
	shell._welcome_seen = false
	shell._cache_state = {
		"ready": true,
		"controlled": true,
		"stored": ["index.wasm", "index.pck"],
		"bytes": 44040192,
		"error": "",
	}
	var first := shell.notice_text()
	_check(
		"TC-BOOT-001: the first visit names the download size",
		first.contains("42 MB"),
		first
	)
	_check(
		"TC-BOOT-001: the first visit asks the tab to stay open",
		first.contains("Keep this tab open"),
		first
	)
	shell._welcome_seen = true
	_check("TC-BOOT-001: a later visit says nothing", shell.notice_text() == "", shell.notice_text())
	shell._cache_state = {
		"ready": true,
		"controlled": true,
		"stored": [],
		"bytes": 44040192,
		"error": "QuotaExceededError",
	}
	var failed := shell.notice_text()
	_check(
		"TC-BOOT-001: a refused cache write is named",
		failed.contains("QuotaExceededError"),
		failed
	)
	_check("TC-BOOT-001: the failure replaces the first-visit line", failed != first, failed)
	Locale.set_current("zh-CN")
	var chinese := shell.notice_text()
	_check(
		"TC-BOOT-001: the failure line is translated too",
		chinese.contains("QuotaExceededError") and chinese != failed,
		chinese
	)
	Locale.set_current("en")
	_check(
		"TC-BOOT-001: the page publishes the payload size",
		shell.payload_label() == "42 MB",
		shell.payload_label()
	)
	shell.queue_free()


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



