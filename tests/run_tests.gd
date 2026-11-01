extends SceneTree
## Headless assertions for the package loader (batch B1).
##
## Run: godot --headless --path . -s res://tests/run_tests.gd
##
## The cases are grouped by the STD case they belong to. Anything that needs a
## browser (the import control, the 2 s list refresh, starting a plugin) stays in
## the manual browser pass; what is asserted here is the pipeline underneath it.

const ENGINE_VERSION := "4.7.2"
const FIXTURE_DIR := "res://.test-tmp"

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
		_package("second", {"id": "test-turn", "name": "Test Turn", "protocol": "turn_based@1", "entry": "n1"}),
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
		"protocol": "turn_based@1",
		"capabilities": ["text", "audio"],
		"mechanics": ["momentum"],
		"entry": "start",
	}, [], [], {"nodes": [{"id": "start", "text": "Start.", "choices": []}]})
	var result := loader.import_bytes(spec_only, _context())
	_check("TC-PKG-005: imports unchanged", result["status"] == "installed", String(result.get("code", "")))
	_check("TC-PKG-005: manifest stored verbatim", String(loader.registry.entry("spec-only-pack")["manifest"]["name"]) == "Spec Only")


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
) -> PackedByteArray:
	## Builds a fixture zip in user:// and returns its bytes. `extra_files` are
	## paths that exist in the zip with dummy content.
	var manifest := _manifest_defaults()
	for key in overrides:
		manifest[key] = overrides[key]
	for key in drop:
		manifest.erase(key)

	var nodes := nodes_override if not nodes_override.is_empty() else {
		"nodes": [{"id": "n1", "text": "A node.", "choices": []}],
	}
	var mechanics := {"rules": [{"when": "state.count > 0", "set": {"state.count": 0}}]}

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
