class_name Shell
extends Control
## The visible shell: landing → plugin list → session → saves → notice.
##
## It decides what the player sees and which core call a click maps to; every
## rule decision stays in `core/`, so the engine is still testable without a
## window (B5a). Nothing here reads storage directly — saves and imported
## packages go through `SaveStore` and `PackageStore`.

const BUILTIN_DIR := "res://builtin"
const SLOT_COUNT := 3

const SCREEN_LANDING := "landing"
const SCREEN_PLUGINS := "plugins"
const SCREEN_SESSION := "session"
const SCREEN_SAVES := "saves"
const SCREEN_NOTICE := "notice"

## The window title carries the screen name. On the web build Godot maps it to
## `document.title`, which is the only piece of the interface a browser driver
## can read without OCR — the scene is one canvas, so button text is pixels.
## It is also honest for a player with many tabs open.
const TITLE_PREFIX := "Lethebar — "

var loader := PackageLoader.new()
var saves := SaveStore.new()
var packages := PackageStore.new()

var screen := SCREEN_LANDING
var session: Session = null
var entry: Dictionary = {}
var notice := {"code": "", "message": ""}
var builtin_ids: Array = []
## Where the loader stages a package while reading it. The browser keeps the
## default; tests point it at a writable res:// folder (SDD §3.1 keeps packages
## in memory, so this is the reader's scratch file, not storage).
var work_dir := "user://pkg"

var _heading: Label
var _sub: Label
var _options: VBoxContainer
var _status: Label


func _ready() -> void:
	_build_chrome()
	_install_builtins()
	show_landing()


# --- screens ----------------------------------------------------------------

func show_landing() -> String:
	## First run starts here. A returning player gets the same screen: the path
	## to a game is one click either way (REQ-017).
	screen = SCREEN_LANDING
	_heading.text = "Lethebar"
	_sub.text = "An engine that ships no gameplay. Pick a pack and play."
	_status.text = ""
	_clear_options()
	_options.add_child(_button("New game", open_plugins))
	if session != null:
		_options.add_child(_button("Continue", enter_session))
	_announce()
	return screen


func open_plugins() -> String:
	screen = SCREEN_PLUGINS
	_heading.text = "Choose a pack"
	_sub.text = "Installed packs. Each one brings its own story and rules."
	_status.text = "" if not builtin_ids.is_empty() else "No pack installed. Stage the built-in packs first."
	_clear_options()
	for plugin_id in builtin_ids:
		var record: Dictionary = loader.registry.entry(plugin_id)
		var manifest: Dictionary = record.get("manifest", {})
		var label := "%s — %s, %s" % [plugin_id, String(manifest.get("protocol", "")), String(manifest.get("version", ""))]
		_options.add_child(_button(label, start_plugin.bind(plugin_id)))
	_options.add_child(_button("Back", show_landing))
	_announce()
	return screen


func start_plugin(plugin_id: String) -> Dictionary:
	## Opens a plugin and starts a session. A player never sees a package that
	## is not on this list, so a failure here is a defect, not a refusal.
	var record: Dictionary = loader.registry.entry(plugin_id)
	if record.is_empty():
		open_notice("E-01", "pack %s is not installed" % plugin_id)
		return current_view()
	entry = record
	session = Session.create(entry, {"start_counter": 1})
	if session == null:
		open_notice("E-02", "pack %s has no usable protocol" % plugin_id)
		return current_view()
	session.start()
	return enter_session()


func choose(index: int) -> Dictionary:
	if session == null:
		return current_view()
	session.choose(index)
	return enter_session()


func enter_session() -> Dictionary:
	screen = SCREEN_SESSION
	_heading.text = "Playing"
	_clear_options()
	var view: Dictionary = current_view()
	_sub.text = String(view.get("text", ""))
	if _sub.text == "":
		_sub.text = "This pack has no scene at the entry point."
	var choices: Array = view.get("choices", [])
	for index in choices.size():
		_options.add_child(_button(String(choices[index].get("label", "")), choose.bind(index)))
	if bool(view.get("finished", false)):
		_heading.text = "The end"
		_options.add_child(_button("Saves", open_saves))
		_options.add_child(_button("Choose another pack", open_plugins))
	else:
		_options.add_child(_button("Saves", open_saves))
		_options.add_child(_button("Back to packs", open_plugins))
	_status.text = _readout(view)
	_announce()
	return view


func open_saves() -> String:
	if session == null:
		return show_landing()
	screen = SCREEN_SAVES
	_heading.text = "Save slots"
	_sub.text = "Three slots for this pack. Loading a slot replaces the current run."
	_status.text = ""
	_clear_options()
	var rows: Array = saves.slots(entry)
	for index in SLOT_COUNT:
		var slot := index + 1
		var row: Dictionary = rows[index] if index < rows.size() else {}
		var description := "Slot %d — empty" % slot
		if not bool(row.get("empty", true)):
			description = "Slot %d — %s" % [slot, String(row.get("preview", ""))]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var text := Label.new()
		text.text = description
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		line.add_child(_button("Save", save_to.bind(slot)))
		line.add_child(_button("Load", load_from.bind(slot)))
		_options.add_child(line)
	_options.add_child(_button("Back", enter_session))
	_announce()
	return screen


func save_to(slot: int) -> Dictionary:
	if session == null:
		return current_view()
	var preview := String(current_view().get("text", "")).left(40)
	var result := saves.write(entry, slot, session.snapshot(), preview)
	open_saves()
	if not bool(result.get("ok", false)):
		_status.text = "Slot %d was not saved: %s" % [slot, String(result.get("code", ""))]
		return current_view()
	_status.text = "Saved to slot %d." % slot
	return current_view()


func load_from(slot: int) -> Dictionary:
	if session == null:
		return current_view()
	var result := saves.read(entry, slot)
	if not bool(result.get("ok", false)):
		open_notice(String(result.get("code", "")), String(result.get("message", "")))
		return current_view()
	session = saves.resume(entry, result["payload"])
	return enter_session()


func open_notice(code: String, message: String) -> String:
	screen = SCREEN_NOTICE
	notice = {"code": code, "message": message}
	_heading.text = "That did not work"
	_sub.text = "%s: %s" % [code, message]
	_status.text = "Nothing was installed. You can pick another pack."
	_clear_options()
	_options.add_child(_button("Back to packs", open_plugins))
	_announce()
	return screen


func try_import(bytes: PackedByteArray) -> Dictionary:
	## Shared by the import button and by tests: a rejected package reports its
	## code on screen and leaves the installed packs untouched (V-01…V-09).
	var result := loader.import_bytes(bytes, _context())
	if String(result.get("status", "")) != "installed":
		open_notice(String(result.get("code", "V-01")), String(result.get("message", "")))
		return current_view()
	var record: Dictionary = result["entry"]
	var plugin_id := String(record.get("id", ""))
	if not builtin_ids.has(plugin_id):
		builtin_ids.append(plugin_id)
	packages.persist(record)
	entry = record
	session = Session.create(entry, {"start_counter": 1})
	session.start()
	return enter_session()


# --- read-only accessors (tests and the smoke probe) ------------------------

func screen_name() -> String:
	return screen


func screen_title() -> String:
	## What the browser tab says. The probe waits for `plugins` here after it
	## clicks "New game", so the title is part of the contract, not decoration.
	return TITLE_PREFIX + screen


func _announce() -> void:
	DisplayServer.window_set_title(screen_title())
	if OS.has_feature("web"):
		# Godot's web build does not forward window titles to the document, so the
		# tab title stays as exported. Mirror the screen onto a plain global that
		# the smoke probe can read; the click that drives it is a real mouse event.
		JavaScriptBridge.eval("window.lethebarScreen = %s;" % JSON.stringify(screen), true)


func current_view() -> Dictionary:
	if session == null:
		if screen == SCREEN_NOTICE:
			return {"node": "", "text": _sub.text, "choices": [], "state": {}, "finished": false, "warnings": [], "code": notice["code"]}
		return {"node": "", "text": "", "choices": [], "state": {}, "finished": false, "warnings": []}
	var view: Dictionary = session.view()
	if screen == SCREEN_NOTICE:
		view["code"] = notice["code"]
	return view


func visible_text() -> String:
	## Everything a player can read on the current screen, buttons included: the
	## stranger-path case asserts on what is visible, not on internal state.
	var parts: Array = []
	if _heading != null:
		parts.append(_heading.text)
	if _sub != null:
		parts.append(_sub.text)
	for child in _options.get_children():
		if child is Button:
			parts.append((child as Button).text)
		elif child is Label:
			parts.append((child as Label).text)
		elif child is HBoxContainer:
			for inner in child.get_children():
				if inner is Label:
					parts.append((inner as Label).text)
				elif inner is Button:
					parts.append((inner as Button).text)
	if _status != null:
		parts.append(_status.text)
	return "\n".join(parts)


# --- construction -----------------------------------------------------------

func _build_chrome() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	scroll.add_child(box)
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 28)
	box.add_child(_heading)
	_sub = Label.new()
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_sub)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	box.add_child(_options)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	box.add_child(_status)


func _install_builtins() -> void:
	builtin_ids.clear()
	for path in _builtin_packages():
		var bytes := FileAccess.get_file_as_bytes(path)
		var result := loader.import_bytes(bytes, _context())
		if String(result.get("status", "")) == "installed":
			builtin_ids.append(String(result["entry"]["id"]))


func _builtin_packages() -> Array:
	## The shell reads the staged directory instead of naming packages: adding a
	## genre must not require editing the render layer, or the point of the plugin
	## layer is lost the moment a second pack ships (B5b card, deviation recorded).
	var found: Array = []
	var directory := DirAccess.open(BUILTIN_DIR)
	if directory == null:
		return found
	for name in directory.get_files():
		if name.ends_with(".zip"):
			found.append("%s/%s" % [BUILTIN_DIR, name])
	found.sort()
	return found


func _clear_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


func _button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(handler)
	return button


func _readout(view: Dictionary) -> String:
	var parts: Array = []
	var state: Dictionary = view.get("state", {})
	for key in state:
		parts.append("%s %s" % [key, str(state[key])])
	if view.has("progress"):
		var progress: Dictionary = view["progress"]
		parts.append("step %d/%d" % [int(progress.get("steps", 0)), int(progress.get("nodes", 0))])
	if parts.is_empty():
		return ""
	return " · ".join(parts)


func _context() -> Dictionary:
	## The loader validates the engine range against the running build, never
	## against a number written down here — a package that needs a newer engine
	## must be refused by the shell the player actually has (V-05).
	var info := Engine.get_version_info()
	return {
		"engine_version": "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])],
		"work_dir": work_dir,
	}
