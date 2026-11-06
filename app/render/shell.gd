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
## One picture band sits between the heading and the prose: a wide slot for the
## scene (or its background fallback) and a narrow one on the right for a
## portrait. Both are hidden when empty, so a text-only pack keeps the layout it
## had before pictures existed (SDD §8.2 — an empty slot takes no space).
var _band: HBoxContainer
var _picture: TextureRect
var _portrait: TextureRect
var _audio: AudioStreamPlayer
var _picture_slots: Array = []
## Set while a desktop picker is open, so a second click does not stack dialogs.
var _picker: FileDialog = null
## The JS callback must stay referenced from here: assigning it to `window` alone
## lets the engine collect it, and the bridge then exists but never calls back.
var _import_callback: JavaScriptObject = null

## The slot whose save is still being folded into durable storage, or zero.
var _saving_slot := 0

## True while a package install is still being folded into durable storage.
var _writing := false

## Frames the browser gets before a write may be called saved. The engine folds
## `user://` into IndexedDB on a scheduled sync and does not expose it to the page,
## so the shell holds the label instead of guessing in seconds.
const FLUSH_MS := 1500
var _flush_started := 0

## The browser's answer to "did you keep the payload": the page shim publishes
## it on `window.lethebarCache`, the shell polls it the way it polls the locale.
var _cache_state: Dictionary = {}

## The notice is shown once per browser; a cleared profile shows it again.
const WELCOME_PATH := "user://welcome.txt"
var _welcome_seen := false

## What the landing screen shows, mirrored into `lethebarState` for the probe.
var _visible_notice := ""


func _ready() -> void:
	_build_chrome()
	resized.connect(_fit_text)
	_fit_text()
	_install_builtins()
	_connect_import_bridge()
	_connect_flush_bridge()
	_read_welcome()
	show_landing()


# --- screens ----------------------------------------------------------------

func show_landing() -> String:
	## First run starts here, and so does every later one. One line says what
	## this is — five first-time players asked exactly that while the screen
	## only described the architecture — then either a new story or the run the
	## player left. The list of stories lives one click away in "New game":
	## putting it here made every visit start with a menu (REQ-017).
	screen = SCREEN_LANDING
	_heading.text = Locale.text("app.name")
	_sub.text = "%s · v%s" % [Locale.text("app.tagline"), version_string()]
	_clear_options()
	_status.text = ""
	_options.add_child(_button(Locale.text("ui.new_game"), open_plugins))
	if not _saves_index().is_empty():
		_options.add_child(_button(Locale.text("ui.continue"), show_loads))
	if builtin_ids.is_empty():
		# Nothing to offer yet, so the screen has to contain the way out of that
		# state rather than a dead end.
		_status.text = Locale.text("ui.no_pack_yet")
		_options.add_child(_button(Locale.text("ui.install"), request_install))
	# The interface is translated, so the player needs a way to say "not my
	# language" without changing the browser.
	_options.add_child(_button(_language_label(), toggle_language))
	var fresh := notice_text()
	if fresh != "":
		_visible_notice = fresh
		# One line, above the buttons, never a modal: a first visit needs to know
		# that 42 MB is arriving and that switching tabs may waste it (REQ-031).
		_sub.text = "%s\n%s" % [_sub.text, fresh]
		_remember_welcome()
	elif _visible_notice != "":
		# The page answers the cache question a frame or two after the first
		# paint; the sentence it replaces must stay until the player leaves this
		# screen, or the notice would blink away in front of them.
		_sub.text = "%s\n%s" % [_sub.text, _visible_notice]
	_announce()
	return screen


func notice_text() -> String:
	## A failed cache write first (the player can act on it), then the size, once.
	var error := String(_cache_state.get("error", ""))
	if error != "":
		return Locale.text("ui.cache_failed") % error
	if _welcome_seen:
		return ""
	var text := Locale.text("ui.first_visit") % payload_label()
	if _is_ios_safari():
		text = "%s %s" % [text, Locale.text("ui.install_hint")]
	return text


func payload_label() -> String:
	## The page publishes this build's exact size; a build without the shim keeps
	## the measured fallback rather than guessing small.
	var bytes := int(_cache_state.get("bytes", 0))
	if bytes <= 0:
		return "42 MB"
	return "%.0f MB" % (float(bytes) / (1024.0 * 1024.0))


func _is_ios_safari() -> bool:
	## Only the iPhone and iPad need the home-screen hint; a browser that is
	## already installed runs in standalone mode and has nothing to add.
	if not OS.has_feature("web"):
		return false
	var answer := str(JavaScriptBridge.eval(
		"(/iPhone|iPad/.test(navigator.userAgent) && !navigator.standalone) ? 1 : 0", true
	))
	return answer == "1"


func _remember_welcome() -> void:
	if _welcome_seen:
		return
	_welcome_seen = true
	var file := FileAccess.open(WELCOME_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("seen\n")
		file.close()


func _read_welcome() -> void:
	if _welcome_seen:
		return
	_welcome_seen = FileAccess.file_exists(WELCOME_PATH)


func show_loads() -> String:
	## `Continue` has no pack in hand, so it lists the saves themselves: one row
	## per non-empty slot, newest first, each opening that pack exactly where the
	## player stopped. Asking "which pack?" first would make "continue" a
	## three-click detour (A + names-only decision, 2026-11-02).
	screen = SCREEN_LOADS
	_heading.text = Locale.text("ui.continue")
	_sub.text = Locale.text("ui.continue_hint")
	_status.text = ""
	_clear_options()
	var rows := _saves_index()
	for row in rows:
		_options.add_child(
			_button(_save_label(row), resume_slot.bind(String(row["plugin"]), int(row["slot"])))
		)
	if rows.is_empty():
		_status.text = Locale.text("ui.nothing_saved")
	_options.add_child(_button(Locale.text("ui.back"), show_landing))
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
	_heading.text = Locale.text("ui.all_packs")
	_sub.text = Locale.text("ui.packs_hint")
	_status.text = "" if not builtin_ids.is_empty() else Locale.text("ui.no_pack_installed")
	_clear_options()
	for plugin_id in builtin_ids:
		_options.add_child(_button(_pack_title(plugin_id), start_plugin.bind(plugin_id)))
	_options.add_child(_button(Locale.text("ui.install"), request_install))
	_options.add_child(_button(Locale.text("ui.back"), show_landing))
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
	session = Session.create(entry, {"start_counter": 1, "locale": Locale.current()})
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


func act(action_id: String) -> Dictionary:
	## One turn of a declared menu (REQ-026). The session decides whether the
	## action is allowed; the scene only redraws what the engine reports.
	if session == null:
		return current_view()
	session.act(action_id)
	return enter_session()


func enter_session() -> Dictionary:
	screen = SCREEN_SESSION
	_heading.text = Locale.text("ui.playing")
	_clear_options()
	var view: Dictionary = current_view()
	_sub.text = String(view.get("text", ""))
	if _sub.text == "":
		_sub.text = Locale.text("ui.no_scene")
	var choices: Array = view.get("choices", [])
	for index in choices.size():
		_options.add_child(_button(String(choices[index].get("label", "")), choose.bind(index)))
	# A package played through actions declares a menu instead of (or beside) its
	# choices. An action that cannot be taken stays visible: the player has to see
	# what is out of reach and why, so the reason becomes part of the label and
	# the button is disabled rather than hidden.
	var actions: Array = view.get("actions", [])
	var run_finished := bool(view.get("finished", false))
	if not run_finished:
		for action in actions:
			var enabled := bool(action.get("enabled", false))
			var label := String(action.get("label", ""))
			var reason := String(action.get("reason", ""))
			if not enabled and reason != "":
				label = Locale.text("ui.blocked") % [label, reason]
			var action_button := _button(label, act.bind(String(action.get("id", ""))))
			action_button.disabled = not enabled
			_options.add_child(action_button)
	var fail_reason := String(view.get("failReason", ""))
	if fail_reason != "":
		_sub.text = Locale.text("ui.run_over") % fail_reason
	if bool(view.get("finished", false)):
		_heading.text = Locale.text("ui.the_end")
		_options.add_child(_button(Locale.text("ui.saves"), open_saves))
		_options.add_child(_button(Locale.text("ui.choose_another"), open_plugins))
	else:
		_options.add_child(_button(Locale.text("ui.saves"), open_saves))
		_options.add_child(_button(Locale.text("ui.back_to_packs"), open_plugins))
	_status.text = _readout(view)
	_show_assets(view)
	_announce()
	return view


func open_saves() -> String:
	if session == null:
		return show_landing()
	screen = SCREEN_SAVES
	_heading.text = Locale.text("ui.save_slots")
	_sub.text = Locale.text("ui.slots_hint")
	_status.text = ""
	_clear_options()
	var rows: Array = saves.slots(entry)
	for index in SLOT_COUNT:
		var slot := index + 1
		var row: Dictionary = rows[index] if index < rows.size() else {}
		var description := Locale.text("ui.slot_empty") % slot
		if not bool(row.get("empty", true)):
			# Saves written before the preview cap still hold their long text, so
			# the clip happens on the way out as well as on the way in.
			description = Locale.text("ui.slot_filled") % [slot, _clip(String(row.get("preview", "")), PREVIEW_CHARS)]
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
	_options.add_child(_button(Locale.text("ui.back"), enter_session))
	_announce()
	return screen


func save_to(slot: int) -> Dictionary:
	if session == null:
		return current_view()
	var preview := _clip(String(current_view().get("text", "")), PREVIEW_CHARS)
	var result := saves.write(entry, slot, session.snapshot(), preview)
	open_saves()
	if not bool(result.get("ok", false)):
		_saving_slot = 0
		_status.text = Locale.text("ui.slot_failed") % [slot, String(result.get("code", ""))]
		return current_view()
	if bool(result.get("pending", false)):
		_saving_slot = slot
		_status.text = Locale.text("ui.saving")
		_announce()
		return current_view()
	_saving_slot = 0
	_status.text = Locale.text("ui.saved_to") % slot
	_announce()
	return current_view()


func poll_saves() -> void:
	## Called every frame. A save that is still being folded into IndexedDB says
	## so, then says it is saved; the slot list is not the place to guess, so the
	## label only changes when the backend answers.
	if _saving_slot < 1 and not _writing:
		return
	if not saves.settled():
		return
	if _writing:
		_writing = false
		_announce()
	if _saving_slot < 1:
		return
	_status.text = Locale.text("ui.saved_to") % _saving_slot
	_saving_slot = 0
	_announce()


func _process(_delta: float) -> void:
	poll_saves()
	_poll_cache_state()


func _poll_cache_state() -> void:
	## The shim answers once per load; until it does, the notice cannot know
	## whether the browser kept the payload, so the shell keeps asking rather than
	## blocking the first frame on a round trip to the worker.
	if bool(_cache_state.get("ready", false)) or not OS.has_feature("web"):
		return
	var raw := str(JavaScriptBridge.eval("JSON.stringify(window.lethebarCache || null)", true))
	if raw.is_empty() or raw == "null":
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_cache_state = parsed
	_cache_state["ready"] = true
	if screen == SCREEN_LANDING:
		show_landing()


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
	_heading.text = Locale.text("ui.failed_heading")
	_sub.text = "%s: %s" % [code, message]
	_status.text = Locale.text("ui.failed_hint")
	_clear_options()
	_options.add_child(_button(Locale.text("ui.back_to_packs"), open_plugins))
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
	saves.mark_writing()
	_writing = true
	entry = record
	session = Session.create(entry, {"start_counter": 1, "locale": Locale.current()})
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

func _connect_flush_bridge() -> void:
	## The browser keeps `user://` in memory and folds it into IndexedDB on a
	## scheduled sync. The export does not expose that sync to the page, so the
	## shell cannot ask for it; what it can do is stop claiming success until the
	## engine has had time to run it. The wait is measured in wall time, not in
	## frames, and it is bounded: a write never reports a slot as saved before
	## the engine had a chance to fold it in.
	if not OS.has_feature("web"):
		return
	saves.flush_request = func() -> void:
		_flush_started = Time.get_ticks_msec()
	saves.flush_probe = func() -> bool:
		## Wall time, not frames: a headless browser draws far faster than sixty
		## frames a second, so a frame budget would be a fraction of the window the
		## storage layer actually needs.
		return Time.get_ticks_msec() - _flush_started >= FLUSH_MS


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


func version_string() -> String:
	## The product version, in one place: `app/project.godot` sets it and this
	## reads it back. A build that somehow lost the setting still reports the
	## three-part shape rather than an empty string, so the assertion below and
	## the browser probe both have something to compare against.
	var raw := String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	if raw.is_empty():
		return "0.0.0"
	return raw


func _language_label() -> String:
	## `Language: English` while English is active, so the button names the
	## language the player is reading rather than the one it switches to.
	var suffix := "zh" if Locale.current() == "zh-CN" else "en"
	return "%s: %s" % [Locale.text("ui.language"), Locale.text("ui.lang_" + suffix)]


func toggle_language() -> void:
	## Two languages, so the switch is a toggle. The choice is stored by
	## `Locale`, which means a reload keeps it (B8).
	var next := "en" if Locale.current() == "zh-CN" else "zh-CN"
	Locale.set_current(next)
	match screen:
		SCREEN_PLUGINS:
			open_plugins()
		SCREEN_SESSION:
			enter_session()
		SCREEN_SAVES:
			open_saves()
		SCREEN_LOADS:
			show_loads()
		_:
			show_landing()


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
			"version": version_string(),
			"locale": Locale.current(),
			"packs": builtin_ids.duplicate(),
			"stories": _story_list(),
			"saves": _saves_index(),
			"slots": slot_previews(),
			"pictures": _picture_slots.duplicate(),
			"status": "" if _status == null else _status.text,
			"saving": _saving_slot > 0 or _writing,
			"notice": _visible_notice if screen == SCREEN_LANDING else "",
			"cache": {
				"controlled": bool(_cache_state.get("controlled", false)),
				"stored": _cache_state.get("stored", []),
				"error": String(_cache_state.get("error", "")),
			},
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
	# The picture band takes a share of the window instead of a fixed 180 px: at
	# 484 px that fixed height pushed the last button below the fold (the probe's
	# screenshot caught it). A share keeps the picture and every button on screen.
	var height := get_viewport_rect().size.y
	# The picture band takes a share of the window, capped by what the text and
	# the buttons leave over. A plain share was enough while the text was Chinese;
	# English wraps to more lines and pushed the last button below the fold (the
	# probe named it: "Back to packs"). Sizing against the other rows keeps every
	# button on screen in both languages.
	var band_share := clampf(height * 0.30, 96.0, 260.0)
	var others := 0.0
	if _box != null:
		for child in _box.get_children():
			var row := child as Control
			if row == null or row == _band or not row.visible:
				continue
			others += row.get_combined_minimum_size().y
		others += float(_box.get_child_count() - 1) * _box.get_theme_constant("separation")
	var room := height - others - 8.0
	_band.custom_minimum_size = Vector2(0.0, clampf(minf(band_share, room), 0.0, 260.0))
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
			# Extents too: a button half below the fold still has its centre on
			# screen, so the centre alone cannot tell a reachable button from a
			# clipped one. The probe checks that the whole box is inside.
			"fw": rect.size.x / size.x,
			"fh": rect.size.y / size.y,
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
	# The picture band is built once and then filled per scene; an empty band
	# collapses to zero height so text-only packs look exactly as they did.
	_band = HBoxContainer.new()
	_band.add_theme_constant_override("separation", 12)
	_band.visible = false
	box.add_child(_band)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picture.custom_minimum_size = Vector2(0.0, 0.0)
	_band.add_child(_picture)
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(160.0, 0.0)
	_band.add_child(_portrait)
	_audio = AudioStreamPlayer.new()
	box.add_child(_audio)
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
	var names: Variant = manifest.get("names", null)
	if names is Dictionary:
		var localized := String(names.get(Locale.current(), ""))
		if not localized.is_empty():
			return localized
	var title := String(manifest.get("name", ""))
	return title if not title.is_empty() else plugin_id


func _story_list() -> Array:
	## Published through `lethebarState` so a browser driver can click a story by
	## the name a player reads instead of guessing at button order. `pictures`
	## says how many pictures the pack declares, so a driver that wants to prove
	## a picture was drawn opens a story that has one instead of whichever comes
	## first (a story with no art draws no band, which is correct, not a defect).
	var stories: Array = []
	for plugin_id in builtin_ids:
		stories.append({
			"id": plugin_id,
			"title": _pack_title(plugin_id),
			"pictures": _declared_pictures(loader.registry.entry(plugin_id)),
		})
	return stories


func _declared_pictures(record: Dictionary) -> int:
	var count := 0
	for asset in record.get("manifest", {}).get("assets", []):
		if asset is Dictionary and String(asset.get("type", "")) == "texture":
			count += 1
	return count


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
	## `<title> · Slot <n> — <preview> · <hh:mm>`, with the clock in the
	## player's own time zone (B8 keeps every word here in the catalogue).
	var label := Locale.text("ui.slot_head") % [String(row.get("title", "")), int(row.get("slot", 0))]
	var preview := _clip(String(row.get("preview", "")), PREVIEW_CHARS)
	if preview != "":
		label += " — " + preview
	var clock := _local_clock(String(row.get("savedAt", "")))
	# The time of day is what tells two saves apart, and the player reads their own.
	if clock != "":
		label += " · " + clock
	return label


func _local_clock(saved_at: String) -> String:
	## `savedAt` is recorded in UTC (`Time.get_datetime_string_from_system(true)`),
	## so printing its time of day told a player in UTC+8 that a 14:20 save happened
	## at 06:20. Convert to this machine's offset before showing it.
	if saved_at.length() < 19:
		return ""
	var utc_seconds := int(Time.get_unix_time_from_datetime_string(saved_at.substr(0, 19)))
	if utc_seconds <= 0:
		return ""
	var bias_minutes := int(Time.get_time_zone_from_system().get("bias", 0))
	var local := Time.get_datetime_dict_from_unix_time(utc_seconds + bias_minutes * 60)
	return "%02d:%02d" % [int(local.get("hour", 0)), int(local.get("minute", 0))]


func _clear_options() -> void:
	for child in _options.get_children():
		_options.remove_child(child)
		child.queue_free()
	_hide_pictures()


func _hide_pictures() -> void:
	## Called by every screen rebuild: a picture belongs to one scene, so leaving
	## the scene takes it away. The band itself only shows when a slot is filled.
	_picture_slots.clear()
	if _band == null:
		return
	_picture.texture = null
	_portrait.texture = null
	_picture.visible = false
	_portrait.visible = false
	_band.visible = false
	if _audio != null:
		_audio.stop()


func _show_assets(view: Dictionary) -> void:
	## Fills the picture slots a scene declares. A slot with no bytes, an unknown
	## slot name, or bytes that do not decode all end the same way: the slot keeps
	## a placeholder, one warning is recorded, and the story goes on (SDD §8.2).
	var data: Dictionary = entry.get("data", {})
	var stored: Dictionary = data.get("assets", {}) if data.get("assets", {}) is Dictionary else {}
	var declared: Variant = view.get("assets", [])
	if not declared is Array:
		return
	for asset in declared:
		if not asset is Dictionary:
			continue
		var asset_type := String(asset.get("type", ""))
		var slot := String(asset.get("slot", _default_slot(asset_type)))
		var path := String(asset.get("path", ""))
		if slot == "scene" or slot == "background":
			_set_slot(_picture, stored, path, slot, view)
		elif slot == "portrait":
			_set_slot(_portrait, stored, path, slot, view)
		elif slot == "audio":
			_set_audio(stored, path, view)
		else:
			_warn(view, "R-01", "unknown asset slot skipped: %s" % slot)


func _default_slot(asset_type: String) -> String:
	## A pack that names no slot still gets sensible placement: pictures become
	## the scene slot, sound becomes audio, and text is drawn as prose already.
	if asset_type == "audio":
		return "audio"
	if asset_type == "text":
		return "text"
	return "scene"


func _set_slot(
	control: TextureRect, stored: Dictionary, path: String, slot: String, view: Dictionary
) -> void:
	var bytes: Variant = stored.get(path, null)
	var texture: Texture2D = null
	if bytes is PackedByteArray and not bytes.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(bytes) == OK or image.load_jpg_from_buffer(bytes) == OK:
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		var placeholder := PlaceholderTexture2D.new()
		placeholder.size = Vector2(320.0, 180.0)
		texture = placeholder
		_warn(view, "R-01", "asset missing or unreadable, placeholder shown: %s" % path)
	control.texture = texture
	control.visible = true
	_band.visible = true
	if not _picture_slots.has(slot):
		_picture_slots.append(slot)


func _set_audio(stored: Dictionary, path: String, view: Dictionary) -> void:
	var bytes: Variant = stored.get(path, null)
	if bytes is PackedByteArray and not bytes.is_empty():
		var stream := AudioStreamWAV.load_from_buffer(bytes)
		if stream != null:
			_audio.stream = stream
			_audio.play()
			return
	_warn(view, "R-01", "sound missing or unreadable, skipped: %s" % path)


func _warn(view: Dictionary, code: String, message: String) -> void:
	if session == null:
		return
	session.warnings.append({"code": code, "message": message, "fatal": false})


func _button(label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(handler)
	return button


func _readout(view: Dictionary) -> String:
	var parts: Array = []
	var state: Dictionary = view.get("state", {})
	var labels: Dictionary = view.get("labels", {})
	for key in state:
		# A declared resource may carry labels: the number stays the state, the
		# label is what a reader sees (engine-bricks §1).
		var shown := String(labels.get(key, ""))
		parts.append("%s %s" % [key, shown if shown != "" else str(state[key])])
	if view.has("progress"):
		var progress: Dictionary = view["progress"]
		parts.append(Locale.text("ui.steps") % [int(progress.get("steps", 0)), int(progress.get("nodes", 0))])
	if view.has("turn"):
		# A package with a phase machine has a turn and a rank; both are the
		# engine's numbers, the scene only reads them (REQ-026).
		parts.append(Locale.text("ui.turn_rank") % [int(view.get("turn", 0)), String(view.get("rank", ""))])
	if view.has("drawn") and not (view["drawn"] as Array).is_empty():
		# What a run has drawn is a fact the player can act on: an action may wait
		# on it, so the scene says it (REQ-027).
		var items: Array = view["drawn"]
		var names := PackedStringArray()
		for item in items:
			names.append(String(item))
		parts.append(Locale.text("ui.drawn") % ", ".join(names))
	if view.has("situation"):
		# How the run stands, read from the same view the buttons use (REQ-033):
		# the time left, who is leaned toward, who is pushed against, what is
		# close to its floor. Every number came from the package, not from here.
		var reading: Dictionary = view["situation"]
		var entity_labels := _entity_labels(view)
		if reading.has("turnsLeft"):
			parts.append(Locale.text("ui.turns_left") % int(reading["turnsLeft"]))
		if reading.has("leaning"):
			var leaned := String(reading["leaning"])
			parts.append(Locale.text("ui.leaning") % String(entity_labels.get(leaned, leaned)))
		if reading.has("friction"):
			var pushed := String(reading["friction"])
			parts.append(Locale.text("ui.friction") % String(entity_labels.get(pushed, pushed)))
		if reading.has("tight"):
			var tight := String(reading["tight"])
			parts.append(Locale.text("ui.tight") % String(labels.get(tight, tight)))
	if parts.is_empty():
		return ""
	return " · ".join(parts)


func _entity_labels(view: Dictionary) -> Dictionary:
	## The scene shows the label a package gave an entity, and falls back to the
	## id so a missing label is still something the player can read.
	var out := {}
	for entity in view.get("factions", []):
		if not (entity is Dictionary):
			continue
		out[String(entity.get("id", ""))] = String(entity.get("label", entity.get("id", "")))
	return out


func _context() -> Dictionary:
	## The loader validates the engine range against the running build, never
	## against a number written down here — a package that needs a newer engine
	## must be refused by the shell the player actually has (V-05).
	var info := Engine.get_version_info()
	return {
		"engine_version": "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])],
		"work_dir": work_dir,
	}
