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
## Save and Load side by side, plus the row's separations, measured once so the
## slot label can be told what width it may take.
const SLOT_BUTTONS_WIDTH := 152.0
## Slot previews are stored with the save, so they are clipped at write time.
const PREVIEW_CHARS := 24

const SCREEN_LANDING := "landing"
const SCREEN_PLUGINS := "plugins"
const SCREEN_SESSION := "session"
const SCREEN_SAVES := "saves"
const SCREEN_LOADS := "loads"
const SCREEN_NOTICE := "notice"

## The window title carries the screen name. On the web build Godot maps it to
## `document.title`, which is the only piece of the interface a browser driver
## can read without OCR — the scene is one canvas, so button text is pixels.
## It is also honest for a player with many tabs open.
const TITLE_PREFIX := "Lethebar — "

var loader := PackageLoader.new()
## Saves and imported packages live in `user://`, which the web build keeps in
## IndexedDB: a slot survives a reload (TC-OFF-001/002/004). Tests swap both
## stores for the memory backend before `_ready()`.
var saves := SaveStore.new(FileBackend.new())
var packages := PackageStore.new(FileBackend.new())

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
var _sub: RichTextLabel
var _options: VBoxContainer
var _status: RichTextLabel
var _margin: MarginContainer
var _box: VBoxContainer
## Set while a desktop picker is open, so a second click does not stack dialogs.
var _picker: FileDialog = null
## The JS callback must stay referenced from here: assigning it to `window` alone
## lets the engine collect it, and the bridge then exists but never calls back.
var _import_callback: JavaScriptObject = null


func _ready() -> void:
	_build_chrome()
	resized.connect(_fit_text)
	_fit_text()
	_install_builtins()
	_connect_import_bridge()
	show_landing()


# --- screens ----------------------------------------------------------------

func show_landing() -> String:
	## First run starts here, and so does every later one. One line says what
	## this is — five first-time players asked exactly that while the screen
	## only described the architecture — then either a new story or the run the
	## player left. The list of stories lives one click away in "New game":
	## putting it here made every visit start with a menu (REQ-017).
	screen = SCREEN_LANDING
	_heading.text = "Lethebar"
	_sub.text = "Short text stories. You choose, and the story goes where you send it."
	_clear_options()
	_status.text = ""
	_options.add_child(_button("New game", open_plugins))
	if not _saves_index().is_empty():
		_options.add_child(_button("Continue", show_loads))
	if builtin_ids.is_empty():
		# Nothing to offer yet, so the screen has to contain the way out of that
		# state rather than a dead end.
		_status.text = "No story is installed yet."
		_options.add_child(_button("Install a pack (.zip)…", request_install))
	_announce()
	return screen


func show_loads() -> String:
	## `Continue` has no pack in hand, so it lists the saves themselves: one row
	## per non-empty slot, newest first, each opening that pack exactly where the
	## player stopped. Asking "which pack?" first would make "continue" a
	## three-click detour (A + names-only decision, 2026-11-02).
	screen = SCREEN_LOADS
	_heading.text = "Continue"
	_sub.text = "Pick up where you left off."
	_status.text = ""
	_clear_options()
	var rows := _saves_index()
	for row in rows:
		_options.add_child(
			_button(_save_label(row), resume_slot.bind(String(row["plugin"]), int(row["slot"])))
		)
	if rows.is_empty():
		_status.text = "Nothing is saved yet."
	_options.add_child(_button("Back", show_landing))
	_announce()
	return screen


func resume_slot(plugin_id: String, slot: int) -> Dictionary:
	## A save names its own plugin, so this is the only entry point that does not
	## start from a pack list. A slot that no longer makes sense in this build
	## (unknown scene, schema drift) is refused with its code, not half-loaded.
	var record: Dictionary = loader.registry.entry(plugin_id)
	if record.is_empty():
		open_notice("E-01", "pack %s is not installed" % plugin_id)
		return current_view()
	var result := saves.read(record, slot)
	if not bool(result.get("ok", false)):
		open_notice(String(result.get("code", "")), String(result.get("message", "")))
		return current_view()
	var restored := saves.resume(record, result["payload"])
	if restored == null:
		open_notice(
			SaveStore.CODE_NODE, "slot %d points at a scene this pack no longer has" % slot
		)
		return current_view()
	entry = record
	session = restored
	return enter_session()


func open_plugins() -> String:
	screen = SCREEN_PLUGINS
	_heading.text = "All packs"
	_sub.text = "Every pack is a story with its own rules. You can add one from a .zip file; it stays in this browser."
	_status.text = "" if not builtin_ids.is_empty() else "No pack installed. Stage the built-in packs first."
	_clear_options()
	for plugin_id in builtin_ids:
		_options.add_child(_button(_pack_title(plugin_id), start_plugin.bind(plugin_id)))
	_options.add_child(_button("Install a pack (.zip)…", request_install))
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
	_sub.text = "Saving keeps your place in this story. Loading a slot goes back to that moment."
	_status.text = ""
	_clear_options()
	var rows: Array = saves.slots(entry)
	for index in SLOT_COUNT:
		var slot := index + 1
		var row: Dictionary = rows[index] if index < rows.size() else {}
		var description := "Slot %d — nothing saved yet" % slot
		if not bool(row.get("empty", true)):
			# Saves written before the preview cap still hold their long text, so
			# the clip happens on the way out as well as on the way in.
			description = "Slot %d — %s" % [slot, _clip(String(row.get("preview", "")), PREVIEW_CHARS)]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var text := Label.new()
		text.text = description
		# A slot row has to leave room for Save and Load. Without wrapping the
		# label's minimum width is the whole sentence, which pushes both buttons
		# past the right edge in a narrow window — and then the player cannot
		# save or load at all. Wrapping plus a pinned width keeps the row inside.
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size = Vector2(_slot_text_width(), 0.0)
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
	var preview := _clip(String(current_view().get("text", "")), PREVIEW_CHARS)
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


# --- installing a pack ------------------------------------------------------

func request_install() -> void:
	## The browser has no file system to browse: the only way to a player's disk
	## is an `<input type="file">`, which `infra/export_web.py` injects next to the
	## canvas and wires to `window.lethebarReceiveFile`. Desktop builds open a
	## native dialog instead, so the same button works when the project runs in
	## the editor.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.lethebarAskForFile && window.lethebarAskForFile();", true)
		return
	if _picker != null and is_instance_valid(_picker):
		_picker.popup_centered_ratio(0.6)
		return
	_picker = FileDialog.new()
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.add_filter("*.zip", "Plugin package")
	_picker.file_selected.connect(_on_file_chosen)
	_picker.canceled.connect(_on_picker_closed)
	add_child(_picker)
	_picker.popup_centered_ratio(0.6)


func _on_picker_closed() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


func _on_file_chosen(path: String) -> void:
	_on_picker_closed()
	install_from_bytes(FileAccess.get_file_as_bytes(path))


func _connect_import_bridge() -> void:
	## The injected input hands the chosen file back as base64, because a
	## JavaScript string is the only thing `JavaScriptBridge` carries. Decoding
	## lives here rather than in JavaScript so the base64 path is covered by the
	## headless suite (`_case_import_control`).
	if not OS.has_feature("web"):
		return
	var window := JavaScriptBridge.get_interface("window")
	_import_callback = JavaScriptBridge.create_callback(_on_file_picked)
	window.lethebarReceiveFile = _import_callback


func _on_file_picked(arguments: Array) -> void:
	if arguments.is_empty():
		return
	install_from_base64(String(arguments[0]))


func install_from_base64(encoded: String) -> Dictionary:
	## What the browser bridge calls. Kept separate from the byte entry point so a
	## test can drive the decode step without a browser.
	return install_from_bytes(Marshalls.base64_to_raw(encoded))


func install_from_bytes(bytes: PackedByteArray) -> Dictionary:
	## One entry for the button, the dialog and the tests. A file the player
	## picked is not more trusted than one that shipped: it goes through the same
	## V-01…V-09 checks and a refusal leaves the installed packs alone.
	return try_import(bytes)


# --- read-only accessors (tests and the smoke probe) ------------------------

func screen_name() -> String:
	return screen


func screen_title() -> String:
	## What the browser tab says. The probe waits for `plugins` here after it
	## clicks "New game", so the title is part of the contract, not decoration.
	return TITLE_PREFIX + screen


func slot_previews() -> Array:
	## Three entries, `""` for an empty slot. The probe uses the first one to
	## tell "the save landed" from "the click missed", and to check after a
	## reload that the slot came back (TC-OFF-002).
	var out: Array = []
	if entry.is_empty():
		return out
	for row in saves.slots(entry):
		out.append("" if bool(row.get("empty", true)) else String(row.get("preview", "")))
	return out


func _announce() -> void:
	DisplayServer.window_set_title(screen_title())
	if OS.has_feature("web"):
		# Godot's web build does not forward window titles to the document, so the
		# tab title stays as exported. Mirror what a driver needs onto one global:
		# which screen is up, which packs are installed, which slots hold a save.
		# Reading it is the only way to assert on a canvas without OCR; every
		# change it reports was still caused by a real click.
		var state := {
			"screen": screen,
			"packs": builtin_ids.duplicate(),
			"stories": _story_list(),
			"saves": _saves_index(),
			"slots": slot_previews(),
		}
		JavaScriptBridge.eval("window.lethebarState = %s;" % JSON.stringify(state), true)
	# Layout is only settled after the frame that added the buttons, so the hit
	# boxes are published one idle frame later. A wrong box makes a click miss,
	# and the assertion on `lethebarState` still has to pass, so this cannot
	# turn a broken screen into a green run.
	call_deferred("_publish_hits")


func _fit_text() -> void:
	## Wrapped text keeps asking for the width of its narrowest column, which
	## grows the whole column far past the window (the probe caught every button
	## sitting below the fold). Pinning the minimum width to the window solves it:
	## the labels then measure their height against the width they really have.
	var width := maxf(get_viewport_rect().size.x - 48.0, 120.0)
	for label in [_sub, _status]:
		if label != null:
			(label as Control).custom_minimum_size = Vector2(width, 0.0)
	# Slot rows hold the same kind of label, but they share the row with two
	# buttons, so they get what is left rather than the full width.
	var slot_width := _slot_text_width()
	for child in _options.get_children():
		if child is HBoxContainer and child.get_child_count() > 0:
			var first := child.get_child(0)
			if first is Label:
				(first as Control).custom_minimum_size = Vector2(slot_width, 0.0)


func _slot_text_width() -> float:
	## Window width minus the margins minus the two buttons on the right.
	return maxf(get_viewport_rect().size.x - 48.0 - SLOT_BUTTONS_WIDTH, 96.0)


func _clip(text: String, limit: int) -> String:
	## Previews are stored, so the cap belongs at write time; the ellipsis keeps
	## it obvious that a longer scene is behind the slot.
	if text.length() <= limit:
		return text
	return text.left(limit) + "…"


func _publish_hits() -> void:
	if not OS.has_feature("web"):
		return
	_fit_text()
	# The labels just changed width, so their height (and every button below
	# them) moves on the next frame; publishing before that would hand the
	# driver yesterday's boxes.
	await get_tree().process_frame
	var hits: Array = []
	# Fractions of the viewport, not pixels: the browser scales the canvas to the
	# window, so the driver converts with `window.innerWidth` and stays correct
	# on any window size.
	var size := get_viewport().get_visible_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_collect_hits(_options, hits, size)
	JavaScriptBridge.eval("window.lethebarHits = %s;" % JSON.stringify(hits), true)


func _collect_hits(node: Node, hits: Array, size: Vector2) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		var button := node as Button
		var rect := button.get_global_rect()
		hits.append({
			"label": button.text,
			"fx": (rect.position.x + rect.size.x / 2.0) / size.x,
			"fy": (rect.position.y + rect.size.y / 2.0) / size.y,
		})
	for child in node.get_children():
		_collect_hits(child, hits, size)


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
	_margin = margin
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_box = box
	_heading = Label.new()
	_heading.add_theme_font_size_override("font_size", 28)
	box.add_child(_heading)
	# `Label` with autowrap reports the height of its narrowest column as its
	# minimum size, which grew the whole column to ~1300 px and pushed every
	# button below a 484 px viewport (caught by the probe's hit boxes, not by
	# looking at the screen). `RichTextLabel` with `fit_content` measures against
	# the width it is actually given, so the column stays the size of the window.
	_sub = RichTextLabel.new()
	_sub.bbcode_enabled = false
	_sub.scroll_active = false
	_sub.fit_content = true
	_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_sub)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 6)
	box.add_child(_options)
	_status = RichTextLabel.new()
	_status.bbcode_enabled = false
	_status.scroll_active = false
	_status.fit_content = true
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("default_color", Color(0.7, 0.7, 0.7))
	box.add_child(_status)


func _install_builtins() -> void:
	builtin_ids.clear()
	for path in _builtin_packages():
		var bytes := FileAccess.get_file_as_bytes(path)
		var result := loader.import_bytes(bytes, _context())
		if String(result.get("status", "")) == "installed":
			builtin_ids.append(String(result["entry"]["id"]))
	# Packages the player imported come back from storage, so a reload does not
	# silently drop a pack they installed (TC-OFF-004). Built-ins are shipped in
	# the pack file and are never stored, so the two lists cannot collide by
	# accident — the `has` check only guards a pack that ships built in later.
	for plugin_id in packages.restore_into(loader, _context()):
		var restored := String(plugin_id)
		if not builtin_ids.has(restored):
			builtin_ids.append(restored)


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


func _pack_title(plugin_id: String) -> String:
	## The player sees the pack's own name, never the protocol it happens to
	## speak: `sanguo — turn_based@1, 0.1.0` looked like a turn-based strategy
	## game and made a first-time player expect internal affairs and troop
	## recruitment (TC-UX-001 finding). Protocol and version stay in the
	## manifest, the log and the error codes, where a developer looks for them.
	var record: Dictionary = loader.registry.entry(plugin_id)
	var manifest: Dictionary = record.get("manifest", {})
	var title := String(manifest.get("name", ""))
	return title if not title.is_empty() else plugin_id


func _story_list() -> Array:
	## Published through `lethebarState` so a browser driver can click a story by
	## the name a player reads instead of guessing at button order.
	var stories: Array = []
	for plugin_id in builtin_ids:
		stories.append({"id": plugin_id, "title": _pack_title(plugin_id)})
	return stories


func _saves_index() -> Array:
	## Every non-empty slot in this browser, newest first. `Continue` needs the
	## saves themselves rather than a pack, because the player remembers the run
	## and not which pack it came from.
	var rows: Array = []
	for plugin_id in builtin_ids:
		var record: Dictionary = loader.registry.entry(plugin_id)
		for row in saves.slots(record):
			if bool(row.get("empty", true)):
				continue
			rows.append({
				"plugin": plugin_id,
				"title": _pack_title(plugin_id),
				"slot": int(row.get("slot", 0)),
				"preview": String(row.get("preview", "")),
				"savedAt": String(row.get("savedAt", "")),
			})
	rows.sort_custom(func(left, right): return String(left["savedAt"]) > String(right["savedAt"]))
	return rows


func _save_label(row: Dictionary) -> String:
	## `三国 · Slot 1 — 初平元年春，关东诸侯会于酸枣… · 12:46`
	var label := "%s · Slot %d" % [String(row.get("title", "")), int(row.get("slot", 0))]
	var preview := _clip(String(row.get("preview", "")), PREVIEW_CHARS)
	if preview != "":
		label += " — " + preview
	var when := String(row.get("savedAt", ""))
	# `2026-11-02T12:46:58` — the time of day is what tells two saves apart.
	if when.length() >= 16:
		label += " · " + when.substr(11, 5)
	return label


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
